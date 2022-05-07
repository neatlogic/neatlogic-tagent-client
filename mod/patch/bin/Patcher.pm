#!/usr/bin/perl
use strict;

package Patcher;

use IO::File;
use FindBin;
use lib "$FindBin::Bin";
use Cwd 'abs_path';
use File::Basename;
use File::Path;
use File::Temp;
use File::Copy;
use POSIX;

sub new {
    my ( $type, $homePath, $backupDir, $backupCount ) = @_;
    my $self     = {};
    my $homePath = abs_path("$FindBin::Bin/..");
    my @uname    = uname();
    my $osType   = 'unix';
    $osType = 'windows' if ( $uname[0] =~ /Windows/i );

    $self->{homePath}    = $homePath;
    $self->{osType}      = $osType;
    $self->{backupDir}   = $backupDir;
    $self->{backupCount} = $backupCount;

    return bless( $self, $type );
}

sub _writePatchDesc {
    my ( $ins, $version, $packFile, $targetType, $targetDir, $backupType, $backupFile ) = @_;
    my $patchDescFile = "$backupFile.desc.txt";
    my $fh            = IO::File->new(">$patchDescFile");

    if ( defined($fh) ) {
        print $fh ("target=$targetDir\n");
        print $fh ("targetType=$targetType\n");
        print $fh ("version=$version\n");
        print $fh ("instance=$ins\n");
        print $fh ("packFile=$packFile\n");
        print $fh ("backupType=$backupType\n");
        print $fh ("backupFile=$backupFile\n");

        $fh->close();
        return 0;
    }

    return -1;
}

sub _walkDir {
    my ( $startPath, $callback ) = @_;

    my $status = 0;
    if ( not -d $startPath ) {
        die("ERROR: destination path:$startPath not a directory.");
    }
    my $curDir = getcwd();
    if ( not chdir($startPath) ) {
        die("ERROR: can not list dir:$startPath.");
    }

    my @dirs = ("./");
    my ( $dir, $file, @statInfo );

    while ( $dir = pop(@dirs) ) {
        local *DH;
        if ( $dir eq "./" ) {
            if ( !opendir( DH, $dir ) ) {
                chdir($curDir);
                die("ERROR: Cannot opendir $startPath: $! $^E");
                return;
            }
            $dir = "";
        }
        else {
            if ( !opendir( DH, $dir ) ) {
                chdir($curDir);
                die("ERROR: Cannot opendir $dir: $! $^E");
                return;
            }
        }

        foreach ( readdir(DH) ) {
            if ( $_ eq "." || $_ eq ".." || $_ eq ".svn" || $_ eq ".git" ) {
                next;
            }

            $file = $dir . $_;
            if ( !-l $file && -d _ ) {
                $file .= "/";
                push( @dirs, $file );
            }
            elsif ( -f $file or -l $file ) {
                my $ret = &$callback($file);
                if ( $ret != 0 ) {
                    die("EROR: backup $file failed.");
                }
            }
        }
        closedir(DH);
    }
    chdir($curDir);
}

sub _backupFiles {
    my ( $self, $reader, $backupFile, $packFile, $regexp ) = @_;
    my $file;
    while ( my $line = <$reader> ) {

        chomp($line);
        if ( not defined($regexp) ) {
            $file = $line;
        }
        elsif ( $line =~ /$regexp/ ) {
            $file = $1;
        }
        else {
            next;
        }

        if ( -e $file ) {
            my $status = system("tar -cvf '$backupFile' '$file'");

            if ( $status != 0 ) {
                print("ERROR: tar '$file' to $backupFile failed.\n");
                unlink($backupFile);
                return -1;
            }
        }
    }
}

sub _backupPackFiles {
    my ( $self, $ins, $version, $backupFile, $packFile, $target ) = @_;

    my $packFilePath = $packFile;

    my $osType = $self->{osType};
    my $reader;
    if ( -d $packFilePath ) {
        my $cb = sub {
            my ($file) = @_;
            my $status = -1;
            if ( $osType eq 'windows' ) {
                $status = system("7z.exec a \"$backupFile\" -ttar \"$file\"");
            }
            else {
                $status = system("tar -cvf '$backupFile' '$file'");
            }

            if ( $status != 0 ) {
                print("ERROR: tar '$file' to '$backupFile' failed.\n");
                unlink($backupFile);
                return -1;
            }

        };

        eval { _walkDir( $target, $cb ); };
        if ($@) {
            print("$@\n");
            return -1;
        }
    }
    elsif ( $packFilePath =~ /\.(zip|war|jar|ear)$/i ) {
        if ( $osType eq 'windows' ) {
            open( $reader, "7z.exe x -l -tzip \"$packFilePath\" |" );
        }
        else {
            open( $reader, "zip -t '$packFilePath' |" );
        }

        $self->_backupFiles( $reader, $backupFile, $packFile, '^testing:\s+(.*?)\s+OK\s*$' );
    }
    elsif ( $packFilePath =~ /\.tar$/i ) {
        if ( $osType eq 'windows' ) {
            open( $reader, "7z.exe x -l -ttar \"$packFilePath\" |" );
        }
        else {
            open( $reader, "tar -tvf '$packFilePath' |" );
        }
        $self->_backupFiles( $reader, $backupFile, $packFile, '\d\d:\d\d\s+(.*?)\s*$' );
    }
    elsif ( $packFilePath =~ /\.(tar\.gz|tgz)/i ) {
        if ( $osType eq 'windows' ) {
            open( $reader, "7z.exe x -tgzip -so \"$packFilePath\" | 7z.exe -x -si -ttar -l |" );
        }
        else {
            open( $reader, "gzip -d -c '$packFilePath' | tar -tvf - |" );
        }
        $self->_backupFiles( $reader, $backupFile, $packFile, '\d\d:\d\d\s+(.*?)\s*$' );
    }

    return 0;
}

sub _backupDelFiles {
    my ( $self, $ins, $version, $backupFile, $packFile, $target ) = @_;
    my $patchFile = "$packFile.patch.txt";
    my $osType    = $self->{osType};

    if ( -f $patchFile ) {
        my $fh = IO::File->new("<$patchFile");
        if ( defined($fh) ) {
            my $line;
            while ( $line = <$fh> ) {
                my @items = split( /\s+/, $line );
                if ( $items[0] eq '-' or $items[0] eq '+' ) {
                    my $file = $items[1];
                    $file =~ s/^\///;
                    $file =~ s/\.\.\///;
                    $file =~ s/\/\.\.//;

                    my $status = -1;
                    if ( $osType eq 'windows' ) {
                        $status = system("7z.exec a \"$backupFile\" -ttar \"$file\"");
                    }
                    else {
                        $status = system("tar -cvf '$backupFile' '$file'");
                    }
                    if ( $status != 0 ) {
                        print("ERROR: tar $file to $backupFile failed.\n");
                        unlink($backupFile);
                        return -1;
                    }
                }
            }
            $fh->close();
        }
        else {
            print("ERROR: Can not open patchFile:$patchFile\n");
        }
    }

    return 0;
}

sub backup {
    my ( $self, $ins, $version, $packFile, $target, $backupType ) = @_;
    my $homePath = $self->{homePath};
    my $osType   = $self->{osType};

    my $backupDir      = $self->{backupDir} . "/$ins.backup";
    my $backupFile     = "$backupDir/$version.bk";
    my $backupCount    = int( $self->{backupCount} );
    my $backupLastDays = $self->{backupLastDays};

    mkpath($backupDir) if ( not -e $backupDir );

    my @backupFiles;
    if ( $osType eq 'windows' ) {
        @backupFiles = glob("\"$backupDir/*.bk\"");
    }
    else {
        @backupFiles = glob("$backupDir/*.bk");
    }

    my @sortedBackupFiles =
        sort { ( stat($a) )[9] <=> ( stat($b) )[9] } @backupFiles;

    my $backupTotalCount = scalar(@sortedBackupFiles);

    my $now = time();
    for ( my $i = 0 ; $i < $backupTotalCount - $backupCount ; $i++ ) {
        my $backup = $sortedBackupFiles[$i];
        my @info   = stat($backup);
        if ( $backupLastDays != -1 and $now - $info[9] > 86400 * $backupLastDays ) {
            unlink($backup);
            unlink("$backup.desc.txt");
        }
    }

    my $status = 0;

    if ( -f "$backupFile" and $backupType eq 'fullbackup' ) {
        $status = 0;
    }
    elsif ( -f $target ) {
        $backupType = 'fullbackup';
        if ( not copy( $target, $backupFile ) ) {
            $status = -1;
            print("ERROR: copy $target to $backupFile failed.\n");
            unlink($backupFile) if ( -f $backupFile );
        }
        else {
            $status = _writePatchDesc( $ins, $version, $packFile, 'file', $target, $backupType, $backupFile );
            if ( $status != 0 ) {
                print("ERROR: can not write backup desc file to $backupFile.desc.txt.\n");
                unlink($backupFile) if ( -f $backupFile );
            }
        }
    }
    elsif ( -d $target ) {
        chdir("$target");

        if ( $backupType eq 'fullbackup' ) {
            if ( $osType eq 'windows' ) {
                $status = system("7z.exe a -ttar -so . | 7z.exe a -tgzip -si \"$backupFile\"");
            }
            else {

                $status = system("tar -cvf - . | gzip > $backupFile");
            }

            if ( $status != 0 ) {
                print("ERROR: tar $target to $backupFile failed.\n");
                unlink($backupFile) if ( -f $backupFile );
            }
        }
        else {
            $status = -1;
            print("ERROR: deltabackup not supported.\n");

            #$status = $self->_backupDelFiles( $ins, $version, $backupFile, $packFile, $target );
            #if ( $status == 0 ) {
            #    $status = $self->_backupPackFiles( $ins, $version, $backupFile, $packFile, $target );
            #}
        }

        if ( $status == 0 ) {
            $status = _writePatchDesc( $ins, $version, $packFile, 'dir', $target, $backupType, $backupFile );
            if ( $status != 0 ) {
                print("ERROR: can not write backup desc file to $backupFile.desc.txt.\n");
                unlink($backupFile) if ( -f $backupFile );
            }
        }
    }
    else {
        print("ERROR: Deploy target path:$target not exists or is not a diectory.\n");
    }

    if ( $status == 0 ) {
        print("INFO: $backupType $target success.\n");
    }
    else {
        print("ERROR: $backupType $target failed.\n");
    }

    return $status;
}

sub deploy {
    my ( $self, $ins, $version, $packFile, $target ) = @_;
    my $status = 0;

    my $homePath = $self->{homePath};
    my $osType   = $self->{osType};

    if ( -d $target ) {
        chdir("$target");

        if ( -d $packFile ) {
            if ( $osType eq 'windows' ) {
                $status = system("xcopy /R /E /Y /I \"$packFile\" .");
            }
            else {
                $status = system("cp -rf '$packFile/.' ./");
            }
        }
        elsif ( $packFile =~ /\.(zip|war|jar|ear)$/i ) {
            if ( $osType eq 'windows' ) {
                $status = system("7z.exe x -aoa -tzip \"$packFile\"");
            }
            else {
                $status = system("unzip -o '$packFile'");
            }
        }
        elsif ( $packFile =~ /\.tar$/i ) {
            if ( $osType eq 'windows' ) {
                $status = system("7z.exe x -aoa -ttar \"$packFile\"");
            }
            else {
                $status = system("tar -xvf '$packFile'");
            }
        }
        elsif ( $packFile =~ /\.(tar\.gz|tgz)/i ) {
            if ( $osType eq 'windows' ) {
                $status = system("7z.exe x -tgzip -so \"$packFile\" | 7z.exe x -ttar -aoa -si");
            }
            else {
                $status = system("gzip -c -d '$packFile' | tar -xvf -");
            }
        }

        if ( $status != 0 ) {
            print("ERROR: unzip $packFile to $target failed.\n");
        }

        my $patchFile = "$packFile.patch.txt";

        #xxx.patch.txt format:
        #- <filepath> #delete file
        #+ <filepath> <mode> #modify permission
        if ( -f $patchFile ) {
            my $fh = IO::File->new("<$patchFile");
            if ( defined($fh) ) {
                my $line;
                while ( $line = <$fh> ) {
                    my @items = split( /\s+/, $line );
                    if ( $items[0] eq '-' ) {
                        my $file = $items[1];
                        $file =~ s/^\///;
                        $file =~ s/\.\.\///;
                        $file =~ s/\/\.\.//;
                        if ( -e $file ) {
                            my $count = unlink($file);
                            print("ERROR: remove $file failed.") if $count = 0;
                        }
                        else {
                            print("ERROR: $file not exists.");
                        }
                    }
                    elsif ( $items[0] eq '+' and $osType ne 'windows' ) {
                        my $file = $items[1];
                        eval {
                            my $mode = oct( $items[2] );
                            $file =~ s/^\///;
                            $file =~ s/\.\.\///;
                            $file =~ s/\/\.\.//;
                            if ( -e $file ) {
                                my $count = chmod( $mode, $file );
                                print("ERROR: chmod $file failed.") if $count = 0;
                            }
                            else {
                                print("ERROR: $file not exists.");
                            }
                        };
                    }
                }
                $fh->close();
            }
            else {
                print("ERROR: Can not open patchFile:$patchFile\n");
            }
        }
    }
    elsif ( -f $target ) {
        my $tmp = File::Temp->new( DIR => "$homePath/tmp", CLEANUP => 1 );
        my $tmpDir = File::Temp->newdir();

        my $ret = 1;
        chdir($tmpDir);
        if ( $osType eq 'windows' ) {
            if ( -f $packFile ) {
                $ret = system("7z.exe x -tzip -aoa \"$packFile\"");
            }
            else {
                $ret = system("xcopy /R /E /Y /I \"$packFile\" .");
            }

            if ( $ret eq 0 ) {
                $ret = system("7z.exe a -tzip \"$target\" .");
            }
        }
        else {
            if ( -f $packFile ) {
                $ret = system("unzip -o -d '$tmpDir' '$packFile'");
            }
            else {
                $ret = system("cp -rf '$packFile/.' ./");
            }

            if ( $ret eq 0 ) {
                $ret = system("zip -r '$target' .");
            }
        }

        chdir($homePath);
        if ( $ret eq 0 ) {
            print("INFO: patch $packFile to $target succeed.\n");
        }
        else {
            print("ERROR: patch $packFile to $target failed.\n");
            exit(-1);
        }
    }
    else {
        print("ERROR: Deploy target path:$target not exists or is not a diectory.\n");
        $status = -1;
    }

    return $status;
}

sub _getParam {
    my ( $path, $key ) = @_;
    my $value = "";
    my $fh    = IO::File->new("<$path");
    while ( my $line = <$fh> ) {
        $line =~ s/^\s*|\s*$//g;
        my @datas = split( /\s*=\s*/, $line );
        if ( $datas[0] eq "$key" ) {
            $value = $datas[1];
            last;
        }
    }
    $fh->close();
    return $value;
}

sub rollback {
    my ( $self, $ins, $version ) = @_;

    my $homePath  = $self->{homePath};
    my $osType    = $self->{osType};
    my $backupDir = $self->{backupDir} . "/$ins.backup";

    my @backups;
    if ( $osType eq 'windows' ) {
        @backups = glob("\"$backupDir/*.bk\"");
    }
    else {
        @backups = glob("$backupDir/*.bk");
    }

    my $hasBackup = 0;
    my $status    = 0;
    foreach my $backup (@backups) {
        if ( $backup =~ /\.bk$/ ) {
            $hasBackup = 1;
            my $backupPath = "$backup.desc.txt";
            my $targetPath = _getParam( $backupPath, 'target' );
            my $targetType = _getParam( $backupPath, 'targetType' );
            my $backupType = _getParam( $backupPath, 'backupType' );

            if ( $targetType eq 'dir' ) {
                chdir("$targetPath");

                if ( $backupType eq 'fullbackup' ) {
                    my $dirH;
                    if ( opendir( $dirH, $targetPath ) ) {
                        my $dir;
                        while ( $dir = readdir($dirH) ) {
                            if ( $dir ne '.' and $dir ne '..' ) {
                                if ( -d $dir ) {
                                    if ( not rmtree($dir) ) {
                                        $status = -1;
                                        last;
                                    }
                                }
                                else {
                                    if ( not unlink($dir) ) {
                                        $status = -1;
                                        last;
                                    }
                                }
                            }
                        }
                    }
                    else {
                        $status = -1;
                    }
                }

                if ( $status == 0 ) {
                    if ( $osType ne 'windows' ) {
                        $status = system("gzip -d -c $backup | tar -xvf -");
                    }
                    else {
                        $status = system("7z.exe x -so -tgzip \"$backup\" | 7z.exe x -si -aoa -ttar");
                    }
                }
            }
            else {
                if ( copy( $backup, $targetPath ) ) {
                    $status = 0;
                }
                else {
                    $status = -1;
                }
            }

            if ( $status == 0 ) {
                print("INFO: unpatch $backup to $targetPath succeed.\n");
            }
            else {
                print("ERROR: unpatch $backup to $targetPath failed.\n");
            }
        }

        if ( $status != 0 ) {
            last;
        }
    }

    if ( $status == 0 ) {
        if ( $hasBackup == 1 ) {

            #foreach my $backup (@backups) {
            #unlink($backup);
            #unlink("$backup.desc.txt");
            #}

            print("INFO: rollback $ins $version success.\n");
        }
        else {
            $status = -1;
            print("ERROR: no backup for $ins $version, rollback failed.\n");
        }
    }
    else {
        print("ERROR: rollback $ins $version failed.\n");
    }

    return $status;
}

1;

