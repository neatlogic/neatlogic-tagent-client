#!/usr/bin/perl
use IO::File;
use strict;
use FindBin;
use lib "$FindBin::Bin";
use Cwd 'abs_path';
use File::Basename;
use File::Path;
use File::Temp;
use File::Copy;
use POSIX;
use CommonConfig;
use Patcher;

my $homePath = abs_path("$FindBin::Bin/..");
my $progName = $FindBin::Script;
my @uname    = uname();
my $osType   = 'unix';
$osType = 'windows' if ( $uname[0] =~ /Windows/i );

sub usage {
    print("Usage:$progName <instance name> <version> <zip|tgz|tar|dir package> <target dir> <fullbackup|deltabackup>\n");
    exit(-1);
}

sub main {
    my $args = scalar(@ARGV);
    usage() if ( $args < 4 );

    if ( $osType eq 'windows' ) {
        $ENV{PATH} = "$homePath/../7-Zip;$ENV{ProgramFiles}/7-Zip;" . $ENV{PATH};
    }

    my $ins        = $ARGV[0];
    my $version    = $ARGV[1];
    my $packFile   = $ARGV[2];
    my $targetDir  = $ARGV[3];
    my $backupType = 'fullbackup';

    my $config = CommonConfig->new( "$homePath/conf", "patch.ini" );

    my $pkgsDir = $config->{"pkgs_dir"};
    if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
        $pkgsDir = "$homePath/pkgs";
    }

    my $backupDir = $config->getConfig('backup_dir');
    if ( not defined($backupDir) or $backupDir eq '' ) {
        $backupDir = $pkgsDir;
    }

    my $backupCount = $config->getConfig('backup_count');
    if ( not defined($backupCount) or $backupCount eq '' ) {
        $backupCount = 3;
    }
    else {
        $backupCount = int($backupCount);
    }

    $backupType = lc( $ARGV[4] ) if ( $args > 4 );
    my $packFilePath = $packFile;
    if ( index( $packFile, '/' ) < 0 ) {
        $packFilePath = "$pkgsDir/$ins/$packFile";
    }

    my $patcher = Patcher->new( $homePath, $backupDir, $backupCount );
    my $status = 0;
    $status = $patcher->backup( $ins, $version, $packFilePath, $targetDir, $backupType );

    if ( $status == 0 ) {
        $status = $patcher->deploy( $ins, $version, $packFilePath, $targetDir );
    }

    if ( $status == 0 ) {
        print("INFO: Deploy $version to $ins with $packFile success.\n");
    }
    else {
        print("ERROR: Deploy $version to $ins with $packFile failed.\n");
    }
    exit($status);
}

main();

