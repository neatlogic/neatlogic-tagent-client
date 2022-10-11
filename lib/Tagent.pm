#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

use strict;

package Tagent;

no warnings;

use English qw( -no_match_vars );
use Errno qw(ETIMEDOUT EWOULDBLOCK EINTR EAGAIN);
use Symbol;
use IPC::Open3;
use Config::Tiny;
use IO::Socket::INET;
use IO::Select;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use Fcntl;
use constant ERROR_BROKEN_PIPE => 109;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );
use File::Glob qw(bsd_glob);

use JSON;
use Cwd;
use File::Basename;
use File::Copy;
use Crypt::RC4;
use Fcntl qw(:flock);

use Config;
use EnvExec;
use TagentClient;
use TagentManager;

#use threads;
my $PROTOCOL_VER        = 'Tagent1.1';
my $SECURE_PROTOCOL_VER = 'Tagent1.1s';

sub _rc4_encrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return join( '', unpack( 'H*', RC4( $key, $data ) ) );
}

sub _rc4_decrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return RC4( $key, pack( 'H*', $data ) );
}

sub _readline($$) {
    my ( $fh, $maxSize ) = @_;
    my $buf;

    my $len;
    my $ch;
    my $k = 0;
    while ( $len = read( $fh, $ch, 1 ) and $len > 0 ) {
        $buf = $buf . $ch;
        $k++;
        if ( $k >= $maxSize or $ch eq "\n" ) {
            last;
        }
    }

    return $buf;
}

sub _pipe {
    socketpair( $_[0], $_[1], AF_UNIX, SOCK_STREAM, PF_UNSPEC )
        or return undef;
    shutdown( $_[0], 1 );    # No more writing for reader
    shutdown( $_[1], 0 );    # No more reading for writer
    return 1;
}

sub _open3 {
    local ( *TO_CHLD_R,     *TO_CHLD_W );
    local ( *FR_CHLD_R,     *FR_CHLD_W );
    local ( *FR_CHLD_ERR_R, *FR_CHLD_ERR_W );

    if ( $^O =~ /Win32/ ) {
        _pipe( *TO_CHLD_R,     *TO_CHLD_W )     or die $^E;
        _pipe( *FR_CHLD_R,     *FR_CHLD_W )     or die $^E;
        _pipe( *FR_CHLD_ERR_R, *FR_CHLD_ERR_W ) or die $^E;
    }
    else {
        pipe( *TO_CHLD_R,     *TO_CHLD_W )     or die $!;
        pipe( *FR_CHLD_R,     *FR_CHLD_W )     or die $!;
        pipe( *FR_CHLD_ERR_R, *FR_CHLD_ERR_W ) or die $!;
    }

    binmode( *TO_CHLD_W,     ':raw' );
    binmode( *FR_CHLD_W,     ':raw' );
    binmode( *FR_CHLD_ERR_W, ':raw' );

    binmode( *TO_CHLD_R,     ':raw' );
    binmode( *FR_CHLD_R,     ':raw' );
    binmode( *FR_CHLD_ERR_R, ':raw' );

    my $pid = open3( '>&TO_CHLD_R', '<&FR_CHLD_W', '<&FR_CHLD_ERR_W', @_ );

    return ( $pid, *TO_CHLD_W, *FR_CHLD_R, *FR_CHLD_ERR_R );
}

sub _close {
    if ( $^O =~ /Win32/ ) {
        foreach my $h (@_) {
            shutdown( $h, 1 );
            close($h);
        }
    }
    else {
        foreach my $h (@_) {
            close($h);
        }
    }
}

sub new {
    my ( $type, $confBase ) = @_;
    my $self = {};

    my $logPath     = "$confBase/logs";
    my $confFile    = "$confBase/conf/tagent.conf";
    my $logFile     = "$confBase/logs/tagent.log";
    my $logLockFile = "$confBase/conf/tagent.lock";

    mkdir($logPath) if ( not -e $logPath );
    my ( $logFileHandle, $logLockFileHandle );
    open( $logFileHandle, ">>$logFile" )
        or die "ERROR: Create log file $logFile failed, $!\n";
    open( $logLockFileHandle, ">$logLockFile" )
        or die "ERROR: Create log lock file $logLockFile failed, $!\n";

    $self->{isStop} = 0;

    $self->{logPurgePenddingCount} = 0;
    $self->{logFileHandle}         = $logFileHandle;
    $self->{logLockFileHandle}     = $logLockFileHandle;

    $self->{confBase} = $confBase;
    $self->{confFile} = $confFile;
    $self->{logFile}  = $logFile;
    $self->{MY_KEY}   = '#ts=9^0$1';

    my $charset = 'UTF-8';

    my @uname  = uname();
    my $ostype = $uname[0];

    $self->{ostype} = $ostype;
    if ( $ostype =~ /Windows/i ) {
        $self->{ostype} = 'windows';

        eval(
            q{
                use Win32::API;
                use Win32API::File qw( GetOsFHandle FdGetOsFHandle SetHandleInformation INVALID_HANDLE_VALUE HANDLE_FLAG_INHERIT );
                use Time::HiRes;

                if ( Win32::API->Import( 'kernel32', 'int GetACP()' ) ) {
                    $charset = 'cp' . GetACP();
                }

                $self->{peekNamedPipeApi} = Win32::API->new('kernel32', 'PeekNamedPipe', 'LLLLLL', 'L') or die $^E;
                $self->{getOsFHandle} = sub {
                    my ($pipe) = @_;
                    my $pHandle = GetOsFHandle( $pipe );
                    if ($pHandle == INVALID_HANDLE_VALUE){
                        die($^E);
                    }
					return $pHandle;
                };

                $self->{usleep} = sub {
                    my ($t) = @_;
                    Time::HiRes::sleep($t);
                };

                $self->{_dont_inherit} = sub {
                    foreach my $handle (@_) {
                        next unless defined($handle);
                        my $fd = $handle;
                        $fd = fileno($fd) if ref($fd);
                             
                        my $osfh = FdGetOsFHandle($fd);
                        if(!defined($osfh) || $osfh == INVALID_HANDLE_VALUE){
                            die($^E);
                        }
                        SetHandleInformation( $osfh, HANDLE_FLAG_INHERIT, 0 );
                    }
                };
            }
        );

        if ($@) {
            print("ERROR:$@\n");
        }

        my $homePath  = Cwd::abs_path("$FindBin::Bin\\..");
        my $toolsPath = "$homePath\\tools";
        my $modPath   = "$homePath\\mod";
        my $tmpPath   = "$homePath\\tmp";

        my $perl5LibPath = Cwd::abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");
        my $perlLibPath  = Cwd::abs_path("$FindBin::Bin/../lib");

        if ( index( $ENV{PERL5LIB}, "$perlLibPath;" ) < 0 ) {
            $ENV{PERL5LIB} = "$perlLibPath;" . $ENV{PERL5LIB};
        }

        if ( index( $ENV{PERL5LIB}, "$perl5LibPath;" ) < 0 ) {
            $ENV{PERL5LIB} = "$perl5LibPath;" . $ENV{PERL5LIB};
        }

        if ( index( $ENV{PATH}, "$toolsPath;$modPath;$tmpPath;" ) < 0 ) {
            $ENV{PATH} = "$toolsPath;$modPath;$tmpPath;" . $ENV{PATH};
        }

        my $path7Zip1 = "$homePath/mod/7-Zip;";
        my $path7Zip2 = $ENV{ProgramFiles} . "/7-Zip;";

        if ( index( $ENV{PATH}, "$path7Zip2;" ) < 0 ) {
            $ENV{PATH} = "$path7Zip2;" . $ENV{PATH};
        }

        if ( index( $ENV{PATH}, "$path7Zip1;" ) < 0 ) {
            $ENV{PATH} = "$path7Zip1;" . $ENV{PATH};
        }

        eval {
            my $perlDir = Cwd::abs_path( dirname( $Config{perlpath} ) );
            if ( index( $ENV{PATH}, "$perlDir;" ) < 0 ) {
                $ENV{PATH} = "$perlDir;" . $ENV{PATH};
            }
        };

        my $procPerlDir = "$homePath/Perl/bin";
        if ( -e $procPerlDir ) {
            if ( index( $ENV{PATH}, "$procPerlDir;" ) < 0 ) {
                $ENV{PATH} = "$procPerlDir;" . $ENV{PATH};
            }
        }
    }
    else {
        $self->{_dont_inherit} = sub {
            foreach my $fd (@_) {
                eval { fcntl( $fd, Fcntl::F_SETFD, Fcntl::FD_CLOEXEC ); };
            }
        };

        eval {
            my $perlDir = Cwd::abs_path( dirname( $Config{perlpath} ) );
            if ( index( $ENV{PATH}, "$perlDir:" ) < 0 ) {
                $ENV{PATH} = "$perlDir:" . $ENV{PATH};
            }
        };

        my ( $lang, $charset );
        my $envLang = $ENV{LANG};

        if ( defined($envLang) and index( $envLang, '.' ) >= 0 ) {
            ( $lang, $charset ) = split( /\./, $envLang );
        }
        else {
            $charset = $envLang;
        }

        $charset = 'iso-8859-1' if ( not defined($charset) );

        my $homePath  = Cwd::abs_path("$FindBin::Bin/..");
        my $toolsPath = "$homePath/tools";
        my $modPath   = "$homePath/mod";
        my $tmpPath   = "$homePath/tmp";

        my $perl5LibPath = Cwd::abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");
        my $perlLibPath  = Cwd::abs_path("$FindBin::Bin/../lib");

        if ( index( $ENV{PERL5LIB}, "$perlLibPath:" ) < 0 ) {
            $ENV{PERL5LIB} = "$perlLibPath:" . $ENV{PERL5LIB};
        }

        if ( index( $ENV{PERL5LIB}, "$perl5LibPath:" ) < 0 ) {
            $ENV{PERL5LIB} = "$perl5LibPath:" . $ENV{PERL5LIB};
        }

        if ( index( $ENV{PATH}, "$toolsPath:$modPath:$tmpPath:" ) < 0 ) {
            $ENV{PATH} = "$toolsPath:$modPath:$tmpPath:" . $ENV{PATH};
        }
    }

    my $_dont_inherit = $self->{_dont_inherit};
    if ( defined($_dont_inherit) ) {
        &$_dont_inherit( $logFileHandle, $logLockFileHandle );
    }

    $self->{charset} = $charset;

    my $config = Config::Tiny->read($confFile);
    $self->{config} = $config;
    bless( $self, $type );

    if ( $config->{_}->{'data.encrypt'} eq 'true' ) {
        $self->{protocolVer} = $SECURE_PROTOCOL_VER;
        $self->{encrypt}     = 1;
    }
    else {
        $self->{protocolVer} = $PROTOCOL_VER;
    }

    my $cred = $self->{config}->{_}->{'credential'};
    if ( $cred !~ /^\{ENCRYPTED\}\s*(.*?)\s*$/i ) {
        $self->_updateCred($cred);
    }

    my $authKeyEncrypted = $self->{config}->{_}->{'credential'};

    my $authKey = $authKeyEncrypted;
    if ( $authKeyEncrypted =~ s/^{ENCRYPTED}\s*// ) {
        $authKey = _rc4_decrypt_hex( $self->{MY_KEY}, $authKeyEncrypted );
    }
    $self->{authKey} = $authKey;

    my $authTimeout = $self->{config}->{_}->{'auth.timeout'};
    $authTimeout = int($authTimeout);
    if ( not defined($authTimeout) or $authTimeout == 0 ) {
        $authTimeout = 86400 * 3650;
    }
    $self->{authTimeout} = $authTimeout;

    my $readTimeout = $self->{config}->{_}->{'read.timeout'};
    $readTimeout = int($readTimeout);
    if ( not defined($readTimeout) or $readTimeout == 0 ) {
        $readTimeout = 5;
    }
    $self->{readTimeout} = $readTimeout;

    my $writeTimeout = $self->{config}->{_}->{'write.timeout'};
    $writeTimeout = int($writeTimeout);
    if ( not defined($writeTimeout) or $writeTimeout == 0 ) {
        $writeTimeout = 15;
    }
    $self->{writeTimeout} = $writeTimeout;

    my $execTimeout = $self->{config}->{_}->{'exec.timeout'};
    if ( not defined($execTimeout) or $execTimeout eq '' ) {
        $execTimeout = 3600;
    }
    else {
        $execTimeout = int($execTimeout);
    }
    $self->{execTimeout} = $execTimeout;

    $self->_purgeLog();

    if ( not -d $confBase ) {
        die("ERROR: Conf base:$confBase not exists.\n");
    }

    if ( not -f $confFile ) {
        $self->log("ERROR: Can not read config file:$confFile.\n");
        die("ERROR: Can not read config file:$confFile.\n");
    }

    $SIG{TERM} = $SIG{INT} = sub {
        $self->{isStop} = 1;
        waitpid( -1, 0 );
        exit(0);
    };

    END {
        local $?;
        if ( defined($self) ) {
            $self->_closeLog();
        }
    }

    return $self;
}

#check if data in pipe to read, only for windows
sub _peekNamedPipe {
    my $self = shift;

    my $nBytesRead;
    my $nTotalBytesAvail;
    my $nBytesLeftThisMessage;

    $nBytesRead            = pack( 'L!', $_[3] ) if defined $_[3];
    $nTotalBytesAvail      = pack( 'L!', $_[4] ) if defined $_[4];
    $nBytesLeftThisMessage = pack( 'L!', $_[5] ) if defined $_[5];

    my $f = $self->{peekNamedPipeApi};

    my $rv = $f->Call(
        $_[0],

        #get_pv($_[1]),
        unpack( 'L!', pack( 'P', $_[1] ) ),
        $_[2],

        #get_pv($nBytesRead),
        unpack( 'L!', pack( 'P', $nBytesRead ) ),

        #get_pv($nTotalBytesAvail),
        unpack( 'L!', pack( 'P', $nTotalBytesAvail ) ),

        #get_pv($nBytesLeftThisMessage),
        unpack( 'L!', pack( 'P', $nBytesLeftThisMessage ) )
    );

    $_[3] = unpack( 'L!', $nBytesRead )            if defined $_[3];
    $_[4] = unpack( 'L!', $nTotalBytesAvail )      if defined $_[4];
    $_[5] = unpack( 'L!', $nBytesLeftThisMessage ) if defined $_[5];

    return $rv;
}

sub register {
    my ($self) = @_;

    my $logger = sub {
        my ($msg) = @_;
        $self->log($msg);
    };

    my $tagentMan = TagentManager->new( $self->{config}, $self->{confFile}, $logger, $self->{MY_KEY}, $self->{_dont_inherit} );
    $self->{tagentManager} = $tagentMan;
    my $newCred = $tagentMan->register();
    if ( defined($newCred) ) {
        my $newCredEncrypted = _rc4_encrypt_hex( $self->{MY_KEY}, $newCred );
        $self->{config}->{_}->{credential} = '{ENCRYPTED}' . $newCredEncrypted;
        $self->{authKey} = $newCred;
    }
}

sub _readChunk {
    my ( $self, $socket, $encrypt ) = @_;

    if ( not defined($encrypt) ) {
        $encrypt = $self->{encrypt};
    }

    my $chunk;

    my $len       = 0;
    my $readLen   = 0;
    my $chunkHead = '';

    my $readTimeout = $self->{readTimeout};
    my $sel         = new IO::Select($socket);
    my @ready;

    $readLen = 0;
    do {
        if ( $readTimeout > 0 ) {
            undef($!);
            @ready = $sel->can_read($readTimeout);
            if ( $!{EINTR} ) {
                next;
            }
        }
        else {
            push( @ready, $socket );
        }

        if ( scalar(@ready) > 0 ) {
            while (1) {
                undef($!);

                my $buf;
                $len = $socket->sysread( $buf, 2 - $readLen );

                if ( not defined($len) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                    next;
                }

                if ( not defined($len) ) {
                    die("Connection reset");
                }
                elsif ( $len == 0 ) {
                    die("Connection closed, $!");
                }
                else {
                    $chunkHead = $chunkHead . $buf;
                    $readLen   = $readLen + $len;
                }

                last;
            }
        }
        else {
            die("Connection read timeout");
        }
    } while ( $readLen < 2 );

    my $chunkLen = unpack( 'n', $chunkHead );

    if ( $chunkLen > 0 ) {
        $chunk   = '';
        $readLen = 0;
        do {
            if ( $readTimeout > 0 ) {
                undef($!);
                @ready = $sel->can_read($readTimeout);
                if ( $!{EINTR} ) {
                    next;
                }
            }
            else {
                push( @ready, $socket );
            }

            if ( scalar(@ready) > 0 ) {
                while (1) {
                    undef($!);

                    my $buf;
                    $len = $socket->sysread( $buf, $chunkLen - $readLen );

                    if ( not defined($len) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                        next;
                    }

                    if ( not defined($len) ) {
                        die("Connection reset");
                    }
                    elsif ( $len == 0 and $readLen < $chunkLen ) {
                        die("Connection closed, $!");
                    }
                    elsif ( $len > 0 ) {
                        $chunk   = $chunk . $buf;
                        $readLen = $readLen + $len;
                    }

                    last;
                }
            }
            else {
                die("Connection read timeout");
            }
        } while ( $readLen < $chunkLen );
    }
    else {
        $chunk   = '';
        $readLen = 0;
        do {
            if ( $readTimeout > 0 ) {
                undef($!);
                @ready = $sel->can_read($readTimeout);
                if ( $!{EINTR} ) {
                    next;
                }
            }
            else {
                push( @ready, $socket );
            }

            if ( scalar(@ready) > 0 ) {
                undef($!);

                my $buf;
                $readLen = $socket->sysread( $buf, 4096 );

                if ( not defined($readLen) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                    next;
                }

                if ( not defined($readLen) ) {
                    die("Connection reset");
                }
                elsif ( $readLen > 0 ) {
                    $chunk = $chunk . $buf;
                }
            }
            else {
                die("Connection read timeout");
            }
        } while ( $readLen > 0 );

        if ( defined($chunk) and $chunk ne '' ) {
            if ( $encrypt == 1 ) {
                $chunk = RC4( $self->{authKey}, $chunk );
            }
            die($chunk);
        }
        else {
            undef($chunk);
        }
    }

    if ( $encrypt == 1 ) {
        if ( defined($chunk) and $chunk ne '' ) {
            $chunk = RC4( $self->{authKey}, $chunk );
        }
    }

    return $chunk;
}

sub _writeChunk {
    my ( $self, $socket, $chunk, $chunkLen, $encrypt ) = @_;

    if ( not defined($encrypt) ) {
        $encrypt = $self->{encrypt};
    }

    if ( defined($chunk) and $chunk ne '' ) {
        if ( $encrypt == 1 ) {
            $chunk = RC4( $self->{authKey}, $chunk );
        }

        if ( not defined($chunkLen) ) {
            $chunkLen = length($chunk);
        }
    }
    else {
        $chunkLen = 0;
    }

    my $isClose = 0;
    if ( $chunkLen == 0 ) {
        $isClose = 1;
    }

    my $writeTimeout = $self->{writeTimeout};
    my $sel          = new IO::Select($socket);
    my @ready;

    my $writeLen      = 0;
    my $totalWriteLen = 0;

    do {
        if ( $writeTimeout > 0 ) {
            undef($!);
            @ready = $sel->can_write($writeTimeout);
            if ( $!{EINTR} ) {
                next;
            }
        }
        else {
            push( @ready, $socket );
        }

        if ( scalar(@ready) > 0 ) {
            undef($!);
            $writeLen = $socket->syswrite( pack( 'n', $chunkLen ), 2 - $totalWriteLen, $totalWriteLen );
            if ( not defined($writeLen) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                next;
            }

            if ( defined($writeLen) ) {
                $totalWriteLen = $totalWriteLen + $writeLen;
            }
            else {
                die("Connection closed, $!");
            }
        }
        else {
            die("Connection write timeout");
        }
    } while ( $totalWriteLen < 2 );

    if ( defined($chunk) ) {
        if ( $chunkLen == 0 ) {
            $chunkLen = length($chunk);
        }

        $writeLen      = 0;
        $totalWriteLen = 0;
        do {
            if ( $writeTimeout > 0 ) {
                undef($!);
                @ready = $sel->can_write($writeTimeout);
                if ( $!{EINTR} ) {
                    next;
                }
            }
            else {
                push( @ready, $socket );
            }

            if ( scalar(@ready) > 0 ) {
                undef($!);
                $writeLen = $socket->syswrite( $chunk, $chunkLen - $totalWriteLen, $totalWriteLen );
                if ( not defined($writeLen) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                    next;
                }

                if ( defined($writeLen) ) {
                    $totalWriteLen = $totalWriteLen + $writeLen;
                }
                else {
                    die("Connection closed, $!");
                }
            }
            else {
                die("Connection write timeout");
            }
        } while ( $totalWriteLen < $chunkLen );
    }

    if ( $isClose == 1 ) {
        $socket->shutdown(1);
    }
}

sub _purgeLog {
    my ($self) = @_;

    $self->{logPurgePenddingCount} = $self->{logPurgePenddingCount} + 1;
    if ( $self->{logPurgePenddingCount} < 100 ) {
        return;
    }
    else {
        $self->{logPurgePenddingCount} = 0;
    }

    my $maxLogFileSize = int( $self->{config}->{_}->{'logfile.size'} );
    my $maxLogCount    = int( $self->{config}->{_}->{'logfile.count'} );
    $maxLogFileSize = 4 * 1024 * 1024 if ( $maxLogFileSize == 0 );
    $maxLogCount    = 4               if ( $maxLogCount == 0 );

    my $logFile       = $self->{logFile};
    my $confBase      = $self->{confBase};
    my $logFileHandle = $self->{logFileHandle};

    if ( not -d "$confBase/logs" ) {
        mkdir("$confBase/logs");
    }
    my @logFiles = sort( glob("$confBase/logs/tagent.log.*") );
    my $logCount = scalar(@logFiles);

    for ( my $i = 0 ; $i < $logCount - $maxLogCount ; $i++ ) {
        unlink( $logFiles[$i] );
    }

    my $currentTime = POSIX::strftime( "%Y%m%d%H%M%S", localtime() );

    my $logFileSize = ( stat $logFile )[7];
    if ( $logFileSize > $maxLogFileSize ) {
        my $logLockFileHandle = $self->{logLockFileHandle};
        flock( $logLockFileHandle, LOCK_EX );
        copy( $logFile, "$logFile.$currentTime" );
        $logFileHandle->truncate(0);
        flock( $logLockFileHandle, LOCK_UN );
    }
}

sub log {
    my ( $self, $msg ) = @_;
    my $logFileHandle     = $self->{logFileHandle};
    my $logLockFileHandle = $self->{logLockFileHandle};

    my $currentTime = POSIX::strftime( "%Y-%m-%d %H:%M:%S", localtime() );
    my $newmsg      = "[$currentTime]$msg";

    flock( $logLockFileHandle, LOCK_SH );
    print $logFileHandle ($newmsg);
    $logFileHandle->flush();
    flock( $logLockFileHandle, LOCK_UN );

}

sub _closeLog {
    my ($self) = @_;
    close( $self->{logFileHandle} );
    close( $self->{logLockFileHandle} );
}

sub auth {
    my ( $self, $clientSock, $addr, $port ) = @_;

    my $authKey = $self->{authKey};

    my $factor1   = int( rand(65433) ) + 1 + int( rand(99) );
    my $factor2   = int( rand(65433) ) + 1 + int( rand(99) );
    my $challenge = "$factor1,$factor2," . time();

    my $encodeChallenge = $self->{ostype} . '|' . $self->{charset} . '|' . _rc4_encrypt_hex( $authKey, $challenge ) . '|' . $self->{protocolVer};

    $self->_writeChunk( $clientSock, $encodeChallenge, length($encodeChallenge), 0 );

    my $clientRes;
    eval {

        $clientRes = $self->_readChunk($clientSock);
        $clientRes =~ s/\s*//;
    };

    if ($@) {
        my $errMsg = $@;
        $errMsg =~ s/\sat\s.*$//;
        $self->_writeChunk( $clientSock, "read auth data failed:$errMsg" );
    }
    else {
        my $chlgRes = _rc4_decrypt_hex( $authKey, $clientRes );
        my ( $chlgKeyStr, $chlgTimeStr ) = split( ',', $chlgRes );
        my $chlgKey  = int($chlgKeyStr);
        my $chlgTime = int($chlgTimeStr);

        if ( $chlgKey == $factor1 * $factor2 ) {
            if ( abs( time() - $chlgTime ) < $self->{authTimeout} ) {

                #$self->log("INFO: Auth succeed from $addr:$port\n");
                $self->_writeChunk( $clientSock, "auth succeed" );
                return 1;
            }
            else {
                $self->log("ERROR: Auth failed from $addr:$port, client time not sync with agent.\n");
            }
        }

        $self->log("ERROR: Auth failed from $addr:$port\n");
        $self->_writeChunk( $clientSock, "auth failed" );
    }
    return 0;
}

sub _updateCred {
    my ( $self, $newAuthKey ) = @_;

    my $newAuthKeyEncoded = _rc4_encrypt_hex( $self->{MY_KEY}, $newAuthKey );
    $self->{config}->{_}->{'credential'} = '{ENCRYPTED}' . $newAuthKeyEncoded;

    my $config   = $self->{config};
    my $confFile = $self->{confFile};
    if ( not $config->write($confFile) ) {
        die($!);
    }
}

sub updateCred {
    my ( $self, $clientSock, $cmd ) = @_;

    $cmd =~ s/^\s*|\s*$//;
    my $newAuthKey = $cmd;
    if ( $newAuthKey =~ /^\{ENCRYPTED\}/ ) {
        $newAuthKey = _rc4_decrypt_hex( $self->{authKey}, $newAuthKey );
    }

    my $statusCode = 200;

    eval { $self->_updateCred($newAuthKey); };
    if ($@) {
        $self->_writeChunk( $clientSock, $!, 0 );
    }
    else {
        $self->_writeChunk( $clientSock, undef, 0 );
    }

    return $statusCode;
}

sub sendReloadReq {
    my ($self) = @_;
    my $config = $self->{config}->{_};

    my $ip      = '127.0.0.1';
    my $port    = $config->{'listen.port'};
    my $authKey = $self->{authKey};

    my $tagentClient = TagentClient->new( $ip, $port, $authKey, 10, 10 );

    return $tagentClient->reload();
}

sub reload {
    my ( $self, $clientSock ) = @_;

    my $statusCode = 200;

    my $ppid;

    if ( $self->{ostype} eq 'windows' ) {
        my $confBase = $ENV{TAGENT_HOME};
        my $progName = $FindBin::Script;
        my $pidFile  = "$confBase/logs/$progName.pid";
        my $pidFh;
        open( $pidFh, "<$pidFile" );
        if ( defined($pidFh) ) {
            my $allPid = <$pidFh>;
            close($pidFh);

            my @pids = split( /\s+/, $allPid );
            $ppid = $pids[0];
        }

        $self->_writeChunk( $clientSock, "Status:$statusCode" );
        $clientSock->close();

        system("taskkill /F /PID $ppid");
    }
    else {
        $ppid = getppid();
        $self->_writeChunk( $clientSock, "Status:$statusCode" );
        $clientSock->close();

        kill( 'USR1', $ppid );
        $self->log("INFO: send reload signal to listen process:$ppid.\n");
    }

    exit(127);

    return $statusCode;
}

sub echo {
    my ( $self, $clientSock, $msg ) = @_;

    my $statusCode = 200;

    $self->_writeChunk( $clientSock, $msg );
    $clientSock->close();

    return $statusCode;
}

sub execCmd {
    my ( $self, $clientSock, $cmd, $eofStr, $isAsync, $envJson, $execTimeout ) = @_;

    my $needTTY = 0;

    if ( defined($envJson) and $envJson ne '' ) {
        eval {
            my $envMap = from_json($envJson);
            foreach my $key ( keys(%$envMap) ) {
                $ENV{$key} = $envMap->{$key};
                if ( $key eq 'TERM' ) {
                    $needTTY = 1;
                }
            }
        };
        if ($@) {
            $self->log( "ERROR: Malform json, " . $@ );
        }
    }

    $cmd =~ s/\$TMPDIR/$ENV{TMPDIR}/g;
    $cmd =~ s/%TMPDIR%/$ENV{TMPDIR}/g;
    $cmd =~ s/\$TAGENT_BASE/$ENV{TAGENT_BASE}/g;
    $cmd =~ s/%TAGENT_BASE%/$ENV{TAGENT_BASE}/g;
    $cmd =~ s/\$TAGENT_HOME/$ENV{TAGENT_HOME}/g;
    $cmd =~ s/%TAGENT_HOME%/$ENV{TAGENT_HOME}/g;

    if ( not defined($execTimeout) ) {
        $execTimeout = $self->{execTimeout};
    }

    my $statusCode = 200;

    if ( defined($isAsync) and $isAsync == 1 ) {
        $statusCode = $self->_execCmdAsync( $clientSock, $cmd, $eofStr, $execTimeout );
    }
    else {
        $statusCode = $self->_readCmdOutLinesToSock( $clientSock, $cmd, $eofStr, $execTimeout, $needTTY );
    }

    return $statusCode;
}

sub _readTarCmdOutToSock {
    my ( $self, $clientSock, $cmd, $fileType, $timeOut ) = @_;

    my $ostype = $self->{ostype};

    my $statusCode = 200;

    my ( $in, $pipe, $err, $pHandle, $pErrHandle );
    my $pid;
    $err = Symbol::gensym();

    eval { $pid = open3( $in, $pipe, $err, $cmd ); };
    if ($@) {
        $statusCode = 500;
        undef($pid);
    }

    if ( defined($pid) and $pid != 0 ) {
        binmode($pipe);

        if ( $ostype eq 'windows' ) {
            my $getOsFHandle = $self->{getOsFHandle};
            $pHandle    = &$getOsFHandle($pipe);
            $pErrHandle = &$getOsFHandle($err);
        }

        $self->_writeChunk( $clientSock, "Status:$statusCode,FileType:$fileType" );

        my $clientSelect = new IO::Select($clientSock);
        my $pipeSelect   = new IO::Select( $pipe, $err );

        my $timeConsume  = 0;
        my $hasException = 0;
        my $isTimeout    = 0;
        my ( $startTime, $endTime );

        my $pipeClosed   = 0;
        my $errMsg       = '';
        my $errMsgLen    = 0;
        my $errMsgMaxLen = 16 * 1024;
        my ( $errBuf, $errLen );
        my ( $buf,    $len );
        $startTime = time();
        while (1) {
            my @pipeReady = $pipeSelect->can_read(2);

            my @clientReady = $clientSelect->can_read(0);
            if ( scalar(@clientReady) > 0 ) {
                eval { $self->_writeChunk( $clientSock, '1', 0 ); };

                my $clientAddr = $clientSock->peerhost();
                my $clientPort = $clientSock->peerport();
                $self->log("ERROR: Client connection($clientAddr:$clientPort) closed, kill command process($pid).\n");

                $hasException = 1;
                if ( $self->{ostype} eq 'windows' ) {
                    system("TASKKILL /F /T /PID $pid");
                }
                else {
                    kill( 'KILL', $pid );
                }
                last;
            }

            if ( defined($timeOut) and $timeConsume > $timeOut ) {
                $isTimeout = 1;

                my $clientAddr = $clientSock->peerhost();
                my $clientPort = $clientSock->peerport();
                $self->log("ERROR: Timeout($clientAddr:$clientPort), kill command process($pid).\n");

                if ( $self->{ostype} eq 'windows' ) {
                    system("TASKKILL /F /T /PID $pid");
                }
                else {
                    kill( 'KILL', $pid );
                }
                last;
            }

            if ( $self->{ostype} ne 'windows' ) {
                if ( scalar(@pipeReady) == 0 ) {
                    $timeConsume = time() - $startTime;
                    next;
                }
                else {
                    foreach my $p (@pipeReady) {
                        if ( $p == $pipe ) {
                            $len = sysread( $pipe, $buf, 8 * 4096 );
                            if ( not defined($len) or $len == 0 ) {
                                $pipeSelect->remove($p);
                            }
                        }
                        elsif ( $p == $err ) {
                            $errLen = sysread( $err, $errBuf, 8 * 4096 );
                            if ( not defined($errLen) or $errLen == 0 ) {
                                $pipeSelect->remove($p);
                            }
                        }
                    }

                    if ( $errLen > 0 ) {
                        $errMsgLen = $errMsgLen + $errLen;
                        $errMsg    = $errMsg . substr( $errBuf, 0, $errLen );
                        if ( $errMsgLen > $errMsgMaxLen ) {
                            $errMsg = substr( $errMsg, index( $errMsg, "\n", $errMsgLen - $errMsgMaxLen ) + 1 );
                        }
                    }
                }
            }
            else {
                my $avail = 0;
                $errLen = 0;
                if ( $self->_peekNamedPipe( $pErrHandle, undef, 0, undef, $avail, undef ) && $avail > 0 ) {
                    $errLen = sysread( $err, $errBuf, 8 * 4096 );
                }

                $avail = 0;
                if ( $pipeClosed == 0 and !$self->_peekNamedPipe( $pHandle, undef, 0, undef, $avail, undef ) ) {
                    if ( $^E != ERROR_BROKEN_PIPE ) {
                        eval { $self->_writeChunk( $clientSock, $^E, 0 ); };
                        last;
                    }
                    else {
                        $pipeClosed = 1;
                    }
                }

                if ( $errLen > 0 ) {
                    $errMsgLen = $errMsgLen + $errLen;
                    $errMsg    = $errMsg . substr( $errBuf, 0, $errLen );
                    if ( $errMsgLen > $errMsgMaxLen ) {
                        $errMsg = substr( $errMsg, index( $errMsg, "\n", $errMsgLen - $errMsgMaxLen ) + 1 );
                    }
                }

                if ( $avail > 0 or $pipeClosed == 0 ) {
                    $len = sysread( $pipe, $buf, 8 * 4096 );
                }
                else {
                    my $usleep = $self->{usleep};
                    &$usleep(0.03);
                }
            }

            if ( $len > 0 ) {
                eval { $self->_writeChunk( $clientSock, $buf, $len ); };
            }
            elsif ( not defined($errLen) or $errLen == 0 ) {
                if ( not $!{EAGAIN} and not $!{EINTR} ) {
                    last;
                }
            }

            $timeConsume = time() - $startTime;
        }

        my $exitPid    = waitpid( $pid, 0 );
        my $exitStatus = $?;
        close($pipe);

        if ( defined($err) ) {
            close($err);
        }

        if ( $hasException != 0 and $exitStatus == 0 ) {
            $exitStatus = -1;
        }

        if ( $isTimeout == 1 ) {
            $self->_writeChunk( $clientSock, "execute timeout($timeOut seconds)", 0 );
        }
        elsif ( $exitStatus ne 0 ) {
            $statusCode = 500;
            $self->_writeChunk( $clientSock, $errMsg, 0 );
        }
        else {
            $statusCode = 200;
            $self->_writeChunk( $clientSock, undef, 0 );
        }
    }
    else {
        $statusCode = 500;
        $self->_writeChunk( $clientSock, "can not launch command on server:$cmd", 0 );
    }

    return $statusCode;
}

sub _readCmdOutLinesToSock {
    my ( $self, $clientSock, $cmd, $eofStr, $timeOut, $needTTY ) = @_;

    my $ostype  = $self->{ostype};
    my $charset = $self->{charset};

    if ( not defined($eofStr) ) {
        $eofStr = '';
    }

    my $statusCode = 200;

    my $exitByFlagLine = 0;

    my ( $in, $pipe, $pHandle );
    my $pid;

    #eval { $pid = open3( undef, $pipe, undef, $cmd ); };
    eval {
        if ( $ostype eq 'windows' ) {
            $pid = open( $pipe, '-|', "$cmd 2>&1" );
        }
        else {
            if ( $needTTY == 1 ) {
                my $pty = IO::Pty->new();

                $pid = fork();

                unless ( defined($pid) ) {
                    warn "Cannot fork: $!" if $^W;
                    return;
                }

                if ($pid) {

                    # parent
                    $pty->close_slave();
                    $pipe = $pty;
                }
                else {

                    # child
                    $pty->make_slave_controlling_terminal();
                    my $slv = $pty->slave()
                        or die "Cannot get slave: $!";

                    close($pty);

                    # wait for parent before we detach
                    close(STDIN);
                    open( STDIN, "<&" . $slv->fileno() )
                        or die "Couldn't reopen STDIN for reading, $!\n";
                    close(STDOUT);
                    open( STDOUT, ">&" . $slv->fileno() )
                        or die "Couldn't reopen STDOUT for writing, $!\n";
                    close(STDERR);
                    open( STDERR, ">&" . $slv->fileno() )
                        or die "Couldn't reopen STDERR for writing, $!\n";

                    { exec($cmd) };
                }

            }
            else {
                $pid = open3( undef, $pipe, undef, $cmd );
            }
        }
        $pipe->autoflush(1);
    };

    #eval { close($in); };
    if ($@) {
        $statusCode = 500;
        undef($pid);
    }

    if ( defined($pid) and $pid != 0 ) {
        if ( $ostype eq 'windows' ) {
            my $getOsFHandle = $self->{getOsFHandle};
            $pHandle = &$getOsFHandle($pipe);
        }

        my $clientSelect = new IO::Select($clientSock);
        my $pipeSelect   = new IO::Select($pipe);

        my $timeConsume  = 0;
        my $hasException = 0;
        my $isTimeout    = 0;
        my ( $startTime, $endTime );

        my $exitStatus = 0;

        my $pipeClosed = 0;
        my $linePrefix = '';
        my $lastLine   = '';
        $startTime = time();
        while ( $statusCode == 200 ) {
            my @pipeReady;
            if ( $ostype ne 'windows' ) {
                @pipeReady = $pipeSelect->can_read(2);
            }

            my @clientReady = $clientSelect->can_read(0);
            if ( scalar(@clientReady) > 0 ) {
                my $clientAddr = $clientSock->peerhost();
                my $clientPort = $clientSock->peerport();
                $clientSock->shutdown(2);
                $self->log("ERROR: Client connection($clientAddr:$clientPort) closed, kill session($self->{sid}).\n");

                $hasException = 1;
                if ( $ostype eq 'windows' ) {
                    system("TASKKILL /F /T /PID $pid");
                }
                else {
                    kill( 'KILL', -$self->{sid} );
                }

                last;
            }

            if ( defined($timeOut) and $timeConsume > $timeOut ) {

                #$hasException = 1;
                $isTimeout = 1;

                my $clientAddr = $clientSock->peerhost();
                my $clientPort = $clientSock->peerport();

                eval { $self->_writeChunk( $clientSock, "execute timeout($timeOut seconds)", 0 ); };
                $self->log("ERROR: Timeout($clientAddr:$clientPort), kill session($self->{sid}).\n");

                if ( $ostype eq 'windows' ) {
                    system("TASKKILL /F /T /PID $pid");
                }
                else {
                    kill( 'KILL', -$self->{sid} );
                }

                last;
            }

            $timeConsume = time() - $startTime;

            if ( $ostype ne 'windows' and scalar(@pipeReady) == 0 ) {
                next;
            }

            my $line;
            if ( $ostype ne 'windows' ) {
                $line = _readline( $pipe, 32768 );

                if ( defined($line) ) {
                    eval { $self->_writeChunk( $clientSock, $line ); };

                    if ( $eofStr ne '' and $line =~ /$eofStr/ ) {
                        $exitByFlagLine = 1;
                        last;
                    }
                    elsif ( $line eq "\x1b[[-=-exec finish-=-\x1b]]\r\n" ) {
                        $exitByFlagLine = 1;
                        $exitStatus     = int( _readline( $pipe, 32768 ) );
                        last;
                    }
                }
                else {
                    if ( not $!{EAGAIN} and not $!{EINTR} ) {
                        last;
                    }
                }

            }
            else {
                my $avail = 0;
                if ( $pipeClosed == 0 and !$self->_peekNamedPipe( $pHandle, undef, 0, undef, $avail, undef ) ) {
                    if ( $^E != ERROR_BROKEN_PIPE ) {
                        eval { $self->_writeChunk( $clientSock, $^E, 0 ); };
                        last;
                    }
                    else {
                        $pipeClosed = 1;
                    }
                }

                if ( $avail > 0 or $pipeClosed == 1 ) {
                    $line = _readline( $pipe, 32768 );
                    if ( defined($line) ) {
                        eval { $self->_writeChunk( $clientSock, $line ); };

                        if ( $eofStr ne '' and $line =~ /$eofStr/ ) {
                            $exitByFlagLine = 1;
                            last;
                        }
                        elsif ( $line eq "\x1b[[-=-exec finish-=-\x1b]]\r\n" ) {
                            $exitByFlagLine = 1;
                            $exitStatus     = int( _readline( $pipe, 32768 ) );
                            last;
                        }
                    }
                    else {
                        if ( not $!{EAGAIN} and not $!{EINTR} ) {
                            last;
                        }
                    }
                }
                elsif ( $pipeClosed == 0 ) {
                    my $usleep = $self->{usleep};
                    &$usleep(0.03);
                }
            }
        }

        if ( $exitByFlagLine == 0 ) {
            my $exitPid = waitpid( $pid, 0 );
            $exitStatus = $?;
        }

        close($pipe);

        if ( $hasException != 0 and $exitStatus == 0 ) {
            $exitStatus = -1;
        }

        if ( $isTimeout == 1 ) {

            #session is killed, code not reach here
            #$self->_writeChunk( $clientSock, "execute timeout($timeOut seconds)", 0 );
        }
        elsif ( $exitStatus ne 0 ) {
            $statusCode = 500;
            if ( $exitStatus > 255 ) {
                $exitStatus = $exitStatus >> 8;
            }
            $self->_writeChunk( $clientSock, "$exitStatus", 0 );
        }
        else {
            $statusCode = 200;
            $self->_writeChunk( $clientSock, undef, 0 );
        }
    }
    else {
        $statusCode = 500;

        $self->_writeChunk( $clientSock, "Launch '$cmd' failed: $!", 0 );
    }

    return $statusCode;
}

sub _execCmdAsync {
    my ( $self, $clientSock, $cmd, $eofStr, $timeOut ) = @_;

    my $ostype  = $self->{ostype};
    my $charset = $self->{charset};

    if ( not defined($eofStr) ) {
        $eofStr = '';
    }

    my $statusCode = 200;

    my $exitByFlagLine = 0;

    my ( $pid, $in, $pipe );
    eval { $pid = open3( $in, $pipe, $pipe, $cmd ); };
    if ($@) {
        $statusCode = 500;
        undef($pid);
    }

    if ( defined($pid) and $pid != 0 ) {
        eval { close($in); };
        if ($@) {
            $self->_writeChunk( $clientSock, "Launch asynchronized '$cmd' failed: $!", 0 );
        }
        else {
            $self->_writeChunk( $clientSock, undef, 0 );
            close($clientSock);
        }

        my $pipeSelect = new IO::Select($pipe);

        my $timeConsume = 0;
        my ( $startTime, $endTime );

        my $exitCode = 0;

        my $linePrefix = '';
        my $lastLine   = '';
        $startTime = time();
        while (1) {
            my @pipeReady;
            if ( $ostype ne 'windows' ) {
                @pipeReady = $pipeSelect->can_read(2);
            }

            if ( defined($timeOut) and $timeConsume > $timeOut ) {
                my $clientAddr = $clientSock->peerhost();
                my $clientPort = $clientSock->peerport();
                $clientPort->shutdown(2);
                $self->log("ERROR: Timeout($clientAddr:$clientPort), kill session($self->{sid}).\n");

                if ( $ostype eq 'windows' ) {
                    system("TASKKILL /F /T /PID $pid");
                }
                else {
                    kill( 'KILL', -$self->{sid} );
                }
                last;
            }

            $timeConsume = time() - $startTime;

            if ( $ostype ne 'windows' and scalar(@pipeReady) == 0 ) {
                next;
            }

            my $line = _readline( $pipe, 32768 );

            if ( not defined($line) ) {
                last;
            }
            elsif ( $eofStr ne '' and $line =~ /$eofStr/ ) {
                $exitByFlagLine = 1;
                last;
            }
            elsif ( $line eq "\x1b[[-=-exec finish-=-\x1b]]\r\n" ) {
                $exitByFlagLine = 1;
                $exitCode       = int( _readline( $pipe, 32768 ) );
                last;
            }
        }

        if ( $exitByFlagLine == 0 ) {
            my $exitPid = waitpid( $pid, 0 );
            $exitCode = $?;
        }

        close($pipe);

        if ( $exitCode ne 0 ) {
            $statusCode = 500;
        }
    }
    else {
        $statusCode = 500;
        $self->_writeChunk( $clientSock, "ERROR: Launch asynchronized '$cmd' failed: $!", 0 );
    }

    return $statusCode;
}

sub _readFileToSock {
    my ( $self, $clientSock, $filePath, $fileType ) = @_;

    my $statusCode = 200;
    my $fh;
    if ( open( $fh, "<$filePath" ) ) {

        $self->_writeChunk( $clientSock, "Status:$statusCode,FileType:$fileType" );

        my ( $len, $buf );
        binmode($fh);
        while ( $len = sysread( $fh, $buf, 8 * 4096 ) ) {
            if ( not $clientSock->connected() ) {
                $statusCode = 500;

                last;
            }

            $self->_writeChunk( $clientSock, $buf, $len );
        }
        $fh->close();

        $self->_writeChunk( $clientSock, undef, 0 );
    }
    else {
        $statusCode = 500;

        #$self->_writeChunk( $clientSock, "Status:$statusCode" );
        $self->_writeChunk( $clientSock, "open file:$filePath failed, $!", 0 );
    }

    return $statusCode;
}

sub download {
    my ( $self, $clientSock, $filePath, $followLinks ) = @_;

    my $followLinksOpt = '';
    if ( $followLinks eq 1 ) {
        $followLinksOpt = 'h';
    }

    my $statusCode = 200;

    if ( defined($filePath) ) {
        my $fileType;

        $filePath =~ s/\$(\w+)/$ENV{$1}/g;
        $filePath =~ s/\$\{(\w+)\}/$ENV{$1}/g;
        $filePath =~ s/\%(\w+)\%/$ENV{$1}/g;

        my $statusCode     = 200;
        my @filePaths      = bsd_glob($filePath);
        my $filePathsCount = scalar(@filePaths);

        if ( $filePathsCount == 0 ) {
            $statusCode = 500;
            $self->_writeChunk( $clientSock, "$filePath not exists.", 0 );
        }
        elsif ( $filePathsCount == 1 and $filePath eq $filePaths[0] ) {
            if ( chdir($filePath) ) {
                $fileType = 'dir';

                if ( $self->{ostype} eq 'windows' ) {
                    $fileType   = 'windir';
                    $statusCode = $self->_readTarCmdOutToSock( $clientSock, "7z.exe a dummy -ttar -y -so .", $fileType );
                }
                else {
                    $statusCode = $self->_readTarCmdOutToSock( $clientSock, "unalias tar >/dev/null 2>&1; tar c${followLinksOpt}f - .", $fileType );
                }
            }
            elsif ( -e $filePath ) {
                $fileType   = 'file';
                $statusCode = $self->_readFileToSock( $clientSock, $filePath, $fileType );
            }
            else {
                $statusCode = 500;
                $self->_writeChunk( $clientSock, "$filePath not exists.", 0 );
            }
        }
        else {
            $self->_writeChunk( $clientSock, "Status:$statusCode,FileType:multiple," . join( '|', @filePaths ) );
        }
    }
    else {
        $statusCode = 500;

        $self->_writeChunk( $clientSock, "blank download path.", 0 );
    }

    return $statusCode;
}

sub upload {
    my ( $self, $clientSock, $fileType, $srcPath, $filePath, $followLinks ) = @_;

    my $followLinksOpt = '';
    if ( $followLinks eq 1 and $self->{ostype} !~ /bsd|drwin/i ) {
        $followLinksOpt = 'h';
    }

    my $statusCode = 200;

    if ( defined($fileType) and defined($srcPath) and defined($filePath) ) {
        $srcPath  =~ s/[\/\\]+/\//g;
        $filePath =~ s/[\/\\]+/\//g;

        $filePath =~ s/\$(\w+)/$ENV{$1}/g;
        $filePath =~ s/\$\{(\w+)\}/$ENV{$1}/g;
        $filePath =~ s/\%(\w+)\%/$ENV{$1}/g;
    }
    else {
        $statusCode = 500;

        $self->_writeChunk( $clientSock, "malform upload request $fileType|$srcPath|$filePath.", 0 );
        return $statusCode;
    }

    my $errMsg;

    if ( $fileType eq 'file' ) {
        if ( -d $filePath ) {
            my $fileName = basename($srcPath);
            $filePath = "$filePath/$fileName";
        }
        elsif ( $filePath =~ /[\/\\]$/ ) {
            my $fileName = basename($srcPath);
            $filePath = $filePath . $fileName;
        }

        my $destDir = dirname($filePath);

        my $fh;
        if ( -d $destDir ) {
            if ( open( $fh, ">$filePath" ) ) {
                binmode($fh);

                $self->_writeChunk( $clientSock, "Status:$statusCode" );

                my $wrtLen = 0;
                my $chunk;
                eval {
                    do {
                        $chunk = $self->_readChunk($clientSock);
                        if ( defined($chunk) ) {
                            $wrtLen = syswrite( $fh, $chunk );
                            if ( not defined($wrtLen) ) {
                                die($!);
                            }
                        }
                    } while ( defined($chunk) );
                };
                if ($@) {
                    $statusCode = 500;
                    close($fh);
                    unlink($filePath);
                    $errMsg = $@;
                    $errMsg =~ s/\sat\s.*$//;
                    $self->log("ERROR:$errMsg");
                }
                else {
                    close($fh);
                    $statusCode = 200;
                }
            }
            else {
                $statusCode = 500;
                $errMsg     = "create $filePath failed:$!";
            }
        }
        else {
            $statusCode = 500;
            $errMsg     = "$destDir not exists.";
        }
    }
    elsif ( $fileType eq 'dir' or $fileType eq 'windir' ) {
        my $maxErrBufLen = 4 * 4096;
        my $errBuf       = '';
        my $errBufLen    = 0;

        my $srcName = basename($srcPath);
        if ( $filePath =~ /[\/\\]$/ and $filePath !~ /$srcName[\/\\]?$/ ) {
            $filePath = $filePath . $srcName;
        }
        $filePath =~ s/[\/\\]$//;

        my $destDir = dirname($filePath);
        my $dest    = basename($filePath);

        if ( not -d $destDir ) {
            $statusCode = 500;
            $errMsg     = "$destDir not exists.";
        }

        elsif ( not -d $filePath and not mkdir($filePath) ) {
            $statusCode = 500;
            $errMsg     = "create $filePath failed:$!";
        }

        elsif ( chdir($filePath) ) {
            my $cmd = "unalias tar >/dev/null 2>\&1; tar x${followLinksOpt}f - 1>/dev/null";
            if ( $self->{ostype} eq 'windows' ) {
                $cmd = "7z.exe x -aoa -y -si -ttar 1>nul";
            }

            my ( $pid, $chldIn, $chldOut, $chldErr );
            eval { ( $pid, $chldIn, $chldOut, $chldErr ) = _open3($cmd); };

            if ( defined($pid) and $pid != 0 ) {
                my $sel = IO::Select->new( $chldOut, $chldErr );

                $self->_writeChunk( $clientSock, "Status:200" );

                my $waitTime = 0;
                my $wrtLen   = 0;
                my $chunk;
                eval {
                    do {
                        $chunk = $self->_readChunk($clientSock);
                        if ( defined($chunk) ) {
                            $wrtLen = syswrite( $chldIn, $chunk );
                            if ( not defined($wrtLen) ) {
                                die($!);
                            }
                        }
                        else {
                            _close($chldIn);
                            $waitTime = 10;
                        }

                        my @pipes;
                        while ( @pipes = $sel->can_read($waitTime) or ( $waitTime > 0 and $sel->count() > 0 ) ) {
                            foreach my $pipe (@pipes) {
                                my $buf;
                                my $len = sysread( $pipe, $buf, 8 * 4096 );

                                if ( $!{EAGAIN} or $!{EINTR} ) {
                                    next;
                                }
                                elsif ( $! and not $!{ECONNRESET} ) {
                                    $sel->remove($pipe);
                                    if ( not $!{ECONNRESET} ) {
                                        $statusCode = 500;
                                        $buf        = ("ERROR: $!\n");
                                        $len        = length($buf);
                                    }
                                }
                                elsif ( not defined($len) or $len <= 0 ) {
                                    $sel->remove($pipe);
                                }

                                if ( defined($len) ) {
                                    $errBuf    = $errBuf . $buf;
                                    $errBufLen = $errBufLen + $len;
                                    if ( $errBufLen > $maxErrBufLen ) {
                                        $errBufLen = substr( $errBufLen, index( $errBuf, "\n", $errBufLen - $maxErrBufLen ) );
                                    }
                                }
                            }
                        }
                    } while ( defined($chunk) );
                };
                if ($@) {
                    $statusCode = 500;
                    $errMsg     = $@;
                    $errMsg =~ s/\sat\s.*$//;
                    $self->log("ERROR: $errMsg");
                    $errMsg = "$errMsg\n$errBuf";
                    _close($chldIn);
                    waitpid( $pid, 0 );
                }
                else {
                    waitpid( $pid, 0 );
                    my $ret = $?;
                    if ( $ret == 0 ) {
                        $statusCode = 200;
                    }
                    else {
                        $statusCode = 500;
                        $errMsg     = "execute tar failed\n$errBuf";
                    }
                }
            }
            else {
                $statusCode = 500;
                $errMsg     = "untar to $filePath failed:$!";
            }
        }
        else {
            $statusCode = 500;
            $errMsg     = "cd directory $filePath failed:$!";
        }
    }
    else {
        $statusCode = 500;
        $errMsg     = "$fileType not supported.";
    }

    if ( $statusCode == 200 ) {
        $self->_writeChunk( $clientSock, undef, 0 );
    }
    else {
        $self->_writeChunk( $clientSock, $errMsg, 0 );
    }

    return $statusCode;
}

sub _getUserGroups {
    my ( $self, $userName ) = @_;
    my ( $user, $passwd, $uid, $gid ) = getpwnam($userName);
    my $group  = getgrgid($gid);
    my @groups = ($gid);

    while ( my ( $grname, $pass, $gid, $members ) = getgrent() ) {
        for my $member ( split( /\s/, $members ) ) {
            if ( $member eq $userName and $grname ne $group ) {
                push( @groups, $gid );
            }
        }
    }

    return @groups;
}

sub _setUid {
    my ( $self, $user ) = @_;

    if ( $self->{ostype} eq 'windows' ) {
        return;
    }

    if ( $< != 0 ) {
        EnvExec::evalProfile( '', $self->{config}->{_} );
        return;
    }

    if ( $user eq 'root' or $user eq 'none' ) {
        EnvExec::evalProfile( '', $self->{config}->{_} );
    }
    else {
        my $uid;

        $uid = getpwnam($user);
        if ( $< ne $uid ) {

            #($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell) = getpwuid($uid);
            my @userInfo  = getpwuid($uid);
            my $userHome  = $userInfo[7];
            my $userShell = $userInfo[8];

            my @userGids = $self->_getUserGroups($user);
            my $gids     = join( ' ', @userGids );
            if ( scalar(@userGids) >= 1 ) {
                $gids = $userGids[0] . ' ' . $gids;
            }
            $gids =~ s/^\s+|\s+$//;

            if ( not defined($uid) or $uid !~ /^\d+$/ ) {
                die("Get uid from [$user] failed, user not exists.");
            }

            EnvExec::evalProfile( $user, $self->{config}->{_} );

            #$GID = $EGID = $gids;
            #$GID <=> $(;  $EGID <=> $)
            undef($!);
            $) = $gids;
            if ( defined($!) and $! ne '' ) {
                die("Set effective group to ($gids) failed: $!\n");
            }

            undef($!);
            $( = $gids;
            if ( defined($!) and $! ne '' ) {
                die("Set user group to ($gids) failed: $!\n");
            }

            #if ( $GID ne $gids or $EGID ne $gids ) {
            #if ( $( ne $gids or $) ne $gids ) {
            #    die("Set run group to ($gids) failed: $!\n");
            #}

            POSIX::setuid($uid);

            #$UID = $EUID = $uid;
            #$UID <=> $<; $EUID <=> $>
            $< = $uid;
            $> = $uid;
            $< = $uid;
            $> = $uid;

            #if ( $UID != $uid ) {
            if ( $< ne $uid or $> ne $uid ) {
                die("Set run user to $user($uid) failed: $!");
            }

            #$ENV{USER} = $user;
            #$ENV{HOME} = $userHome;
        }
    }

    return;
}

sub handleRequest {
    my ( $self, $clientSock, $addr, $port ) = @_;
    my $cmdLine;

    my $statusCode = 200;

    eval { $cmdLine = $self->_readChunk($clientSock); };

    if ($@) {
        $statusCode = 500;
        my $errMsg = $@;
        $errMsg =~ s/\sat\s.*$//;
        $self->_writeChunk( $clientSock, "read request failed, client:$addr:$port:$errMsg", 0 );
        return $statusCode;
    }

    my $cmdLen = length($cmdLine);

    if ( $cmdLen == 0 ) {
        $statusCode = 500;

        $self->_writeChunk( $clientSock, "request protocol error, empty request, client:$addr:$port.", 0 );
        return $statusCode;
    }

    my $reqCmd = $cmdLine;
    $reqCmd =~ s/^\s*|\s*$//;

    if ( $reqCmd eq '' ) {
        $statusCode = 500;

        $self->_writeChunk( $clientSock, "request protocol error, blank request, client:$addr:$port.", 0 );
        return $statusCode;
    }

    my @request    = split( '\|', $reqCmd );
    my $paramCount = scalar(@request);

    if ( $paramCount < 4 ) {
        $statusCode = 500;

        $self->_writeChunk( $clientSock, "request protocol error, separate request failed, client:$addr:$port.", 0 );
        return $statusCode;
    }

    my $user    = $request[0];
    my $reqType = $request[1];
    my $charset = $request[2];

    for ( my $i = 3 ; $i < $paramCount ; $i++ ) {
        $request[$i] = pack( 'H*', $request[$i] );
    }

    if ( $reqType eq 'updatecred' ) {
        $self->log("ACC: [begin] $addr:$port $user $reqType $charset\n");
    }
    else {
        #127.0.0.1:57992 none echo UTF-8 heartbeat, do not record log
        if ( $addr ne '127.0.0.1' or $request[1] ne 'echo' ) {
            $self->log( "ACC: [begin] $addr:$port " . join( ' ', @request ) . "\n" );
        }
    }

    my $startTime = time();

    if ( $reqType ne 'reload' ) {
        eval { $self->_setUid($user); };
        if ($@) {
            $self->log("ERROR:set uid failed, $@");
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;

            $statusCode = 500;

            $self->_writeChunk( $clientSock, $errMsg, 0 );
        }
    }

    if ( $statusCode eq 200 ) {
        if ( $reqType eq 'execmd' ) {
            if ( $paramCount > 6 ) {
                $statusCode = $self->execCmd( $clientSock, $request[3], $request[4], 0, $request[5], int( $request[6] ) );
            }
            elsif ( $paramCount == 5 ) {
                $statusCode = $self->execCmd( $clientSock, $request[3], $request[4], 0, $request[5] );
            }
            else {
                $statusCode = $self->execCmd( $clientSock, $request[3], $request[4], 0 );
            }
        }
        elsif ( $reqType eq 'execmdasync' ) {
            if ( $paramCount > 6 ) {
                $statusCode = $self->execCmd( $clientSock, $request[3], $request[4], 1, $request[5], int( $request[6] ) );
            }
            elsif ( $paramCount == 5 ) {
                $statusCode = $self->execCmd( $clientSock, $request[3], $request[4], 1, $request[5] );
            }
            else {
                $statusCode = $self->execCmd( $clientSock, $request[3], $request[4], 1 );
            }
        }
        elsif ( $reqType eq 'download' ) {
            $statusCode = $self->download( $clientSock, $request[3], $request[4], $request[5] );
        }
        elsif ( $reqType eq 'upload' ) {
            $statusCode = $self->upload( $clientSock, $request[3], $request[4], $request[5], $request[6] );
        }
        elsif ( $reqType eq 'updatecred' ) {
            $statusCode = $self->updateCred( $clientSock, $request[3] );
        }
        elsif ( $reqType eq 'reload' ) {
            $statusCode = $self->reload($clientSock);
        }
        elsif ( $reqType eq 'echo' ) {
            $statusCode = $self->echo( $clientSock, $request[3] );
        }
    }

    $clientSock->close();
    my $timeConsume = time() - $startTime;

    if ( $reqType eq 'updatecred' ) {
        $self->log("ACC: [end] $addr:$port $user $reqType $statusCode\n");
    }
    else {
        #127.0.0.1:57992 none echo UTF-8 heartbeat, do not record log
        if ( $addr ne '127.0.0.1' or $request[1] ne 'echo' ) {
            $self->log( "ACC: [end] $addr:$port " . join( ' ', @request ) . " $statusCode time:$timeConsume second\n" );
        }
    }
}

sub startManager {
    my ($self) = @_;
    my $tagentMan = $self->{tagentManager};

    while (1) {
        eval { $tagentMan->mainLoop(); };
        if ($@) {
            $self->log("ERROR: manager failed: $@\n");
        }
    }
}

sub start {
    my ($self) = @_;

    my $socket;
    my ( $peeraddress, $peerport );

    $| = 1;

    my $listen  = $self->{config}->{_}->{'listen.addr'};
    my $port    = $self->{config}->{_}->{'listen.port'};
    my $backlog = $self->{config}->{_}->{'listen.backlog'};

    $listen  = '0.0.0.0' if ( not defined($listen)  or $listen eq '' );
    $port    = 3939      if ( not defined($port)    or $port eq '' );
    $backlog = 16        if ( not defined($backlog) or $backlog eq '' );

    # creating object interface of IO::Socket::INET modules which internally does
    # socket creation, binding and listening at the specified port address.
    my $socketType = SOCK_STREAM;
    if ( $self->{ostype} ne 'windows' ) {
        eval(q{$socketType = Socket::SOCK_STREAM | Socket::SOCK_CLOEXEC;});
    }

    $socket = new IO::Socket::INET(
        LocalHost => $listen,
        LocalPort => $port,
        Type      => $socketType,
        Proto     => 'tcp',
        Listen    => $backlog,
        Reuse     => 1
    ) or die "ERROR in Socket Creation : $!\n";

    my $_dont_inherit = $self->{_dont_inherit};
    if ( defined($_dont_inherit) ) {
        &$_dont_inherit($socket);
    }

    END {
        local $?;
        if ( defined($socket) ) {
            $socket->close();
        }
    }

    $self->log( "INFO: start with PATH=" . $ENV{PATH} . "\n" );
    $self->log("INFO: Waiting for client connection on port $port\n");

    if ( $self->{ostype} ne 'windows' ) {
        $SIG{'CHLD'} = 'IGNORE';

        $SIG{'USR1'} = sub {
            $socket->close();

            my $childPid;
            do {
                $childPid = waitpid( -1, WNOHANG );
                if ( $childPid == 0 ) {
                    $childPid = waitpid( -1, 0 );
                }
            } while ( $childPid != -1 );

            my $ppid = getppid();
            $self->log("INFO: send reload signal to parent process:$ppid.\n");
            kill( 'USR1', $ppid );
            exit(0);
        };
    }

    my %childPids;

    while ( $self->{isStop} == 0 ) {
        eval {
            $self->_purgeLog();

            my $pid = 0;

            my $clientSocket;
            my $clientAddr;
            my $clientPort;

            # waiting for new client connection.
            my $sel   = new IO::Select($socket);
            my @ready = $sel->can_read(3);
            if ( scalar(@ready) > 0 ) {
                $clientSocket = $socket->accept();

                next if ( not defined($clientSocket) );

                my $_dont_inherit = $self->{_dont_inherit};
                if ( defined($_dont_inherit) ) {
                    &$_dont_inherit($clientSocket);
                }

                # get the host and port number of newly connected client.
                $clientAddr = $clientSocket->peerhost();
                my $clientPort = $clientSocket->peerport();
                binmode($clientSocket);
                $pid = fork();

                if ( not defined($pid) or $pid != 0 ) {
                    eval {
                        $clientSocket->close();

                        if ( not defined($pid) ) {
                            $self->log("ERROR: can not fork child process to service:$clientAddr:$clientPort(maybe out of memroy or max process exceeded)$!.\n");
                        }

                        if ( $self->{ostype} eq 'windows' ) {
                            if ( defined($pid) ) {
                                $childPids{$pid} = undef;
                            }
                        }
                    };
                    if ($@) {
                        $self->log("ERROR: $@");
                    }
                }
                else {
                    if ( $self->{ostype} ne 'windows' ) {
                        setsid();
                        $self->{sid} = $$;
                    }

                    eval {
                        $socket->close();

                        if ( $self->{ostype} ne 'windows' ) {
                            $SIG{'CHLD'} = undef;
                            $SIG{'USR1'} = undef;
                            $SIG{'PIPE'} = 'IGNORE';
                        }

                        if ( $self->auth( $clientSocket, $clientAddr, $clientPort ) == 1 ) {
                            eval { $self->handleRequest( $clientSocket, $clientAddr, $clientPort ); };
                            if ($@) {
                                $self->log("ERROR: $clientAddr:$clientPort handle reqeust failed:$@\n");
                            }
                        }
                        else {
                            $clientSocket->close();
                            $self->log("ERROR: Auth $clientAddr:$clientPort failed.\n");
                        }
                    };
                    if ($@) {
                        $self->log("ERROR: $clientAddr:$clientPort $@");
                    }
                    exit(0);
                }
            }

            #Windows的fork出来是线程模拟的进程pseudo-process, 需要主动reap，否则超过64个pseduo-process后会fork失败
            if ( $self->{ostype} eq 'windows' ) {
                my $isReload = 0;

                foreach my $childPid ( keys(%childPids) ) {
                    my $exitPid    = waitpid( $childPid, WNOHANG );
                    my $exitStatus = $?;

                    if ( $exitPid != 0 ) {
                        delete( $childPids{$childPid} );

                        #用于处理windows的reload重启
                        if ( $exitPid != -1 ) {
                            if ( $exitStatus == 127 * 256 ) {
                                $isReload = 1;
                            }
                        }

                        #windows判断是否reload结束
                    }
                }

                #isReload只会在windows生效，如果被置位则退出主循环
                if ( $isReload == 1 ) {
                    last;
                }
            }
        };
        if ($@) {
            $self->log("ERROR: accept connection failed:$@");
            if ( $self->{ostype} eq 'windows' ) {
                last;
            }
        }
    }
}

1;

