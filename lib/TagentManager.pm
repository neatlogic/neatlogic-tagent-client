#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

use strict;
use warnings;

package TagentManager;

#use Socket;
use English qw( -no_match_vars );
use Errno qw(ETIMEDOUT EWOULDBLOCK EINTR);
use HTTP::Tiny;
use IO::Socket::INET;
use IO::Select;

#use JSON::Simple;
use JSON;
use TagentClient;
use Crypt::RC4;
use Config;
use Sys::Hostname;
use File::Basename;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use Distribution;

sub _rc4_encrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return join( '', unpack( 'H*', RC4( $key, $data ) ) );
}

sub _rc4_decrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return RC4( $key, pack( 'H*', $data ) );
}

sub randPass {
    my ($self) = @_;

    my @chars = ( 'A' .. 'Z', 'a' .. 'z', '0' .. '9' );
    my $pass;

    for ( my $i = 0 ; $i < 16 ; $i++ ) {
        $pass = $pass . $chars[ rand @chars ];
    }

    return $pass;
}

sub hashStrToInt {
    my ( $self, $str ) = @_;

    my $hashVal = unpack( "%32N*", $str ) % 65535;
    return $hashVal;
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $content;

    if ( -f $filePath ) {
        my $size = -s $filePath;
        my $fh   = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }
    }

    return $content;
}

sub collectIp {
    my @uname    = uname();
    my $osType   = $uname[0];
    my $ipString = "";
    my @ipList;
    if ( $osType =~ /Windows/i ) {
        @ipList = `ipconfig /all | findstr "IP"`;
    }
    else {
        @ipList = `ifconfig -a 2>/dev/null`;
        if ( $? != 0 ) {
            @ipList = `ip addr 2>/dev/null`;
        }
    }

    my $allIps = {};
    foreach (@ipList) {
        my $ip = $_;
        if ( $ip =~ /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/ ) {
            if ( $1 > 0 and $1 < 255 and $2 >= 0 and $2 <= 255 and $3 >= 0 and $3 <= 255 and $4 >= 0 and $4 < 255 ) {
                my $realIp = "$1.$2.$3.$4";
                if ( not defined( $allIps->{$realIp} ) ) {
                    if ( $realIp ne '127.0.0.1' ) {
                        $ipString = $ipString . $realIp . ',';
                    }
                    $allIps->{$realIp} = 1;
                }
            }
        }
    }
    $ipString = substr( $ipString, 0, rindex( $ipString, ',' ) );

    return $ipString;
}

# tagent register , succeed return 1
sub new {
    my ( $type, $config, $confFile, $logger, $myKey, $_dont_inherit ) = @_;
    my $self = {};
    bless( $self, $type );

    my @uname  = uname();
    my $ostype = $uname[0];
    if ( $ostype =~ /Windows/i ) {
        $ostype = 'windows';
    }
    $ostype = lc($ostype);
    $self->{ostype} = $ostype;

    my $confDir         = dirname($confFile);
    my $appsConfFile    = "$confDir/managed/apps.json";
    my $appsConfMd5File = "$confDir/managed/apps.json.md5";

    if ( -f $appsConfFile ) {
        eval {
            my $appsJson = $self->getFileContent($appsConfFile);
            my $appsConf = from_json($appsJson);

            foreach my $app ( keys(%$appsConf) ) {

                my $appConf     = $appsConf->{$app};
                my $defaultConf = $appConf->{default};
                my $myOsConf    = $appConf->{$ostype};

                if ( not defined($myOsConf) ) {
                    $appConf->{$ostype} = $defaultConf;
                }
                else {
                    foreach my $key ( keys(%$defaultConf) ) {
                        if ( not defined( $myOsConf->{$key} ) ) {
                            $myOsConf->{$key} = $defaultConf->{$key};
                        }
                    }
                }
            }
            $self->{appsConf} = $appsConf;

            my $appsJsonMd5 = $self->getFileContent($appsConfMd5File);
            $self->{appsConfMd5} = $appsJsonMd5;
        };
        if ($@) {
            &$logger("WARN: parse json file:$appsConfFile failed.\n");
        }
    }

    $self->{confDir}       = $confDir;
    $self->{config}        = $config;
    $self->{confFile}      = $confFile;
    $self->{MY_KEY}        = $myKey;
    $self->{logger}        = $logger;
    $self->{_dont_inherit} = $_dont_inherit;
    $self->{appsStatus}    = {};
    $self->{loopInterval}  = 10;

    return $self;
}

sub getVersion {
    return '1.5.2';
}

sub _getWinScriptExt {
    my ( $self, $interpreter ) = @_;

    my $extName;
    if ( not defined($interpreter) ) {
        $extName = '.bat';
    }
    elsif ( $interpreter =~ /powershell/i ) {
        $extName = '.ps1';
    }
    elsif ( $interpreter =~ /perl/i ) {
        $extName = '.pl';
    }
    elsif ( $interpreter =~ /cscript/i ) {
        $extName = '.vbs';
    }
    elsif ( $interpreter =~ /python/i ) {
        $extName = '.py';
    }
    elsif ( $interpreter =~ /cmd/i ) {
        $extName = '.bat';
    }
    else {
        $extName = '.bat';
    }

    return $extName;
}

sub register {
    my ($self) = @_;

    my $config     = $self->{config}->{_};
    my $logger     = $self->{logger};
    my $tagentName = hostname();

    my @uname     = uname();
    my $osType    = $uname[0];
    my $release   = $uname[2];
    my $osVersion = $uname[3];
    if ( $osType =~ /Windows/i ) {
        $osType = 'windows';
    }
    $self->{ostype} = lc($osType);
    my $ostype    = $self->{ostype};
    my $ipString  = collectIp();
    my $ipHashVal = $self->hashStrToInt($ipString);
    $self->{ipHashVal} = $ipHashVal;

    my $tagentVersion   = getVersion();
    my $tagentId        = $config->{'tagent.id'};
    my $tenant          = $config->{'tenant'};
    my $credential      = $config->{'credential'};
    my $port            = $config->{'listen.port'};
    my $registerAddress = $config->{'proxy.registeraddress'};

    my $user  = 'root';
    my $osbit = 'x86';
    if ( $ostype eq 'windows' ) {
        $user = 'administrator';

        $osbit = `wmic os get osarchitecture 2>nul | findstr /i /v osarchitecture`;
        if ( $? != 0 ) {
            $osbit = `echo %PROCESSOR_ARCHITECTURE%`;
        }
        if ( $osbit =~ /64/ ) {
            $osbit = 'x64';
        }
        else {
            $osbit = 'x86';
        }

        my $caption = `wmic os get caption 2>nul | findstr /i /v caption`;
        $caption =~ s/[^[:ascii:][:print:]]//g;
        $caption =~ s/\?\s*/ /g;
        $caption =~ s/^\s*|\s*$//g;

        $osVersion =~ s/[^[:ascii:][:print:]]//g;
        $osVersion =~ s/^\s*|\s*$//g;
        $osVersion = $caption . '_' . $osVersion;
    }
    else {
        $user = getpwuid($<);
        if ( not defined($user) or $user eq '' ) {
            $user = 'root';
        }
        if ( $ostype eq 'aix' ) {
            $osVersion = `oslevel -s`;
            $osbit     = `bootinfo -K`;
            if ( $osbit =~ /64/ ) {
                $osbit = 'x64';
            }
        }
        else {
            $osbit = $uname[4];
            eval {
                my $dist = Distribution->new();

                my $distName = $dist->distribution_name();
                if ( defined($distName) ) {
                    my $version = $dist->distribution_version();
                    if ( not defined($version) ) {
                        $version = '';
                    }
                    $osVersion = "${distName}${version}_${release}";
                }
            };
            if ($@) {
                &$logger("WARN: get os distribute info failed, $@\n");
            }
        }
    }

    #&$logger("INFO: cpu bit is $ipString ======================\n");

    my $postData = {
        tenant     => $tenant,
        tagentId   => $tagentId,
        user       => $user,
        port       => $port,
        ipString   => $ipString,
        name       => $tagentName,
        version    => $tagentVersion,
        osType     => $ostype,
        osVersion  => $osVersion,
        osbit      => $osbit,
        credential => $credential
    };

    if ( defined($registerAddress) and $registerAddress ne '' ) {
        &$logger("INFO: try to register, register address is $registerAddress, tagent:$user:$port\n");

        my $authKeyEncrypted;
        my $newPass;
        if ( not defined($tagentId) or $tagentId eq '' ) {
            $newPass                = $self->randPass();
            $authKeyEncrypted       = '{ENCRYPTED}' . _rc4_encrypt_hex( $self->{MY_KEY}, $newPass );
            $postData->{credential} = $authKeyEncrypted;
        }

        my $registSucceed = 0;

        while (1) {
            if ( not defined($registerAddress) or $registerAddress eq '' ) {
                &$logger("WARN: Please check you conf， register address is not configed!\n");
                return;
            }
            else {

                #&$logger( "DEBUG: post data is :".from_json($postData). "end\n" );
                my @proxyAddresses = split( /\s*,\s*/, $registerAddress );
                if ( scalar(@proxyAddresses) > 1 ) {
                    my $startIdx       = $ipHashVal % scalar(@proxyAddresses);
                    my @headProxyAddrs = splice( @proxyAddresses, 0, $startIdx );
                    push( @proxyAddresses, @headProxyAddrs );
                }

                foreach my $proxyAddress (@proxyAddresses) {
                    my $http     = HTTP::Tiny->new( timeout => 15 );
                    my $response = $http->post(
                        $proxyAddress => {
                            content => to_json($postData),
                            headers => { "Content-Type" => "application/json", "User-Agent" => "Mozilla/5.0" },
                        },
                    );
                    if ( $response->{status} == 200 ) {
                        eval {
                            my $retval = from_json( $response->{content} );

                            #&$logger( " DEBUG: from_json", $response->{content}, "\n" );
                            if ( "OK" eq $retval->{"Status"} or "SUCCEED" eq $retval->{"Status"} ) {
                                my @group = ();
                                my $data  = $retval->{"Data"};
                                $tagentId = $data->{"tagentId"};
                                my $proxyGroupId = $data->{"proxyGroupId"};
                                my @proxyList    = @{ $data->{'proxyList'} };
                                foreach my $proxy (@proxyList) {
                                    my $address = $proxy->{"ip"} . ":" . $proxy->{"port"};
                                    push( @group, $address );
                                }
                                my $proxyGroup = join( ',', @group );
                                $config->{'tagent.id'} = $tagentId;
                                if ( defined($authKeyEncrypted) ) {
                                    $config->{'credential'} = $authKeyEncrypted;
                                }

                                if ( scalar(@group) > 0 ) {
                                    $config->{'proxy.group'} = join( ',', @group );
                                }
                                if ( defined($proxyGroupId) and $proxyGroupId ne '' ) {
                                    $config->{'proxy.group.id'} = $proxyGroupId;
                                }
                                if ( not $self->{config}->write( $self->{confFile} ) ) {
                                    &$logger("ERROR: Update config file failed after registered:$!\n");
                                    die("Update config file failed after registered:$!\n");
                                }

                                $registSucceed = 1;
                                &$logger("INFO: Registry success, tagent id:$tagentId, proxy group:$proxyGroup.\n");
                            }
                            else {
                                &$logger( "ERROR: Tagent register failed:" . $retval->{'Message'} . "\n" );
                                sleep(3);
                            }
                        };
                        if ($@) {
                            &$logger( "ERROR: Tagent register return:" . $response->{content} . "\n" );
                            &$logger("ERROR: Tagent register failed:$@\n");
                            sleep(3);
                        }
                        else {
                            if ( $registSucceed eq 1 ) {
                                last;
                            }
                        }
                    }
                }
            }

            if ( $registSucceed == 0 ) {
                sleep(5);
            }
            else {
                last;
            }
        }

        return $newPass;
    }
    else {
        &$logger("INFO: Registry Address is empty, running in standalone mode.\n");
        return;
    }
}

#connect with proxy
sub getConnection {
    my ($self) = @_;

    my $config = $self->{config}->{_};
    my $logger = $self->{logger};

    my $group      = $config->{'proxy.group'};
    my $tagentId   = int( $config->{'tagent.id'} );
    my $listenAddr = $config->{'listen.addr'};

    my $socket;

    if ( defined($group) and $group ne '' ) {
        my $socketType = SOCK_STREAM;
        if ( $self->{ostype} ne 'windows' ) {
            eval(q{$socketType = Socket::SOCK_STREAM | Socket::SOCK_CLOEXEC;});
        }

        my @proxyList  = split( /,/, $group );
        my $proxyCount = scalar(@proxyList);

        #根据tagentId的值进行proxy的优先选择
        my $startIdx = 0;
        if ( $proxyCount > 0 ) {
            $startIdx = $self->{ipHashVal} % $proxyCount;
            if ( $startIdx > 0 ) {
                my @headProxy = splice( @proxyList, 0, $startIdx );
                push( @proxyList, @headProxy );
            }
        }

        my $loopCount = 1;
        while (1) {
            foreach my $proxy (@proxyList) {
                my @address = split( /:/, $proxy );
                for ( my $i = 1 ; $i < 3 ; $i++ ) {
                    if ( defined($listenAddr) and $listenAddr eq '0.0.0.0' ) {
                        $socket = IO::Socket::INET->new(
                            PeerAddr => $address[0],
                            PeerPort => $address[1],
                            Proto    => "tcp",
                            Type     => $socketType
                        );
                    }
                    else {
                        $socket = IO::Socket::INET->new(
                            LocalAddr => $listenAddr,
                            PeerAddr  => $address[0],
                            PeerPort  => $address[1],
                            Proto     => "tcp",
                            Type      => $socketType
                        );
                    }

                    my $_dont_inherit = $self->{_dont_inherit};
                    if ( defined($_dont_inherit) ) {
                        &$_dont_inherit($socket);
                    }

                    if ( not defined($socket) ) {
                        &$logger("WARN: connect to server @address failed.\n");
                        sleep( 20 * $i + rand( 20 * $i ) );
                    }
                    else {
                        last;
                    }
                }

                if ( defined($socket) ) {
                    $self->{proxyIp}    = $address[0];
                    $self->{proxyPort}  = int( $address[1] );
                    $self->{serverAddr} = $address[0] . ':' . $address[1];
                    last;
                }
            }

            if ( defined($socket) ) {
                &$logger( "INFO: server " . $self->{serverAddr} . " connected.\n" );
                last;
            }
            else {
                &$logger("ERROR: connect to server $group failed:$!\n");
                sleep( 3 * $loopCount + rand( 3 * $loopCount ) );
            }
            $loopCount = $loopCount + 1;
        }
    }
    return $socket;
}

sub _resetCred {
    my ($self) = @_;
    my $config = $self->{config}->{_};
    my $logger = $self->{logger};

    my $newPass          = $self->randPass();
    my $authKeyEncrypted = '{ENCRYPTED}' . _rc4_encrypt_hex( $self->{MY_KEY}, $newPass );

    $config->{'credential'} = $authKeyEncrypted;
    if ( not $self->{config}->write( $self->{confFile} ) ) {
        &$logger("WARN:  Update config file failed $!\n");
    }

    $self->_reload();
}

sub _reload {
    my ($self) = @_;

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

        #kill($ppid);
        system("taskkill /F /PID $ppid");
    }
    else {
        $ppid = getppid();
        kill( 'USR1', $ppid );
    }

    exit(127);
}

sub _execModuleAction {
    my ( $self, $app, $action ) = @_;
    my $logger = $self->{logger};

    my $appsConf = $self->{appsConf};
    my $ostype   = $self->{ostype};
    my $appConf  = $appsConf->{$app};

    my $myAppConf  = $appConf->{$ostype};
    my $actionConf = $myAppConf->{$action};

    my $interpreter;
    if ( not defined($actionConf) ) {
        next;
    }

    $interpreter = $actionConf->{interpreter};
    if ( $interpreter eq '' ) {
        undef($interpreter);
    }

    my $confDir = $self->{confDir};
    my $logFile = "$confDir/../logs/${app}_${action}.log";

    my $cmd;
    if ( $ostype eq 'windows' ) {
        if ( not defined($interpreter) or $interpreter =~ /^\s*cmd\s*$/ ) {
            $interpreter = 'cmd /c';
        }

        my $extName = $self->_getWinScriptExt($interpreter);
        $cmd = "\"$confDir/managed/$app/$action$extName\" > \"$logFile\" 2>&1";
        $cmd =~ s/\//\\/g;
        $cmd = "$interpreter $cmd";
    }
    else {
        if ( not defined($interpreter) ) {
            $interpreter = 'sh';
        }
        $cmd = "$interpreter '$confDir/managed/$app/$action' > '$logFile' 2>&1";
    }

    my $ret = 0;
    my $pipe;
    my $pid = open( $pipe, '-|', $cmd );
    if ( defined($pipe) ) {
        my $loopCount = 300;
        while ( waitpid( $pid, WNOHANG ) == 0 and $loopCount > 0 ) {
            sleep(1);
            $loopCount--;
        }

        if ( $loopCount <= 0 ) {
            if ( $ostype eq 'windows' ) {
                system("TASKKILL /F /T /PID $pid");
            }
            else {
                kill( 'KILL', $pid );
            }
        }
        else {
            $ret = $?;
        }

        if ( $ret ne 0 ) {
            &$logger("ERROR: execute app:$app action:$action cmd:$cmd, ret:$ret failed.\n");
        }
        close($pipe);
    }
    else {
        &$logger("ERROR: lauch app:$app action:$action cmd:$cmd failed:$!\n");
    }
}

sub _upgrade {
    my ($self) = @_;

    # 解压文件
    # system("tar -zxvf  /opt/tagent/run/root/tmp/tagent.tar.gz /opt/tmp/");

}

sub _updateAppsConf {
    my ( $self, $data ) = @_;
    my $logger   = $self->{logger};
    my $appsConf = $data->{apps};
    my $appsMd5  = $data->{md5};
    my $ostype   = $self->{ostype};
    my $confDir  = $self->{confDir};

    if ( not -e "$confDir/managed" ) {
        mkdir("$confDir/managed");
    }

    my $appsConfMd5File = "$confDir/managed/apps.json.md5";
    my $appsConfFile    = "$confDir/managed/apps.json";

    my $file = IO::File->new(">$appsConfFile");
    if ( defined($file) ) {
        print $file ( to_json($appsConf) );
        $file->close();
    }

    my @keysTmp = ( 'monitor', 'start', 'stop', 'install', 'uninstall' );
    foreach my $app ( keys(%$appsConf) ) {

        my $appConf     = $appsConf->{$app};
        my $defaultConf = $appConf->{default};
        my $myOsConf    = $appConf->{$ostype};

        if ( not defined($myOsConf) ) {
            $appConf->{$ostype} = $defaultConf;
            $myOsConf = $defaultConf;
        }
        else {
            foreach my $key ( keys(%$defaultConf) ) {
                if ( not defined( $myOsConf->{$key} ) ) {
                    $myOsConf->{$key} = $defaultConf->{$key};
                }
            }
        }

        my %validKeys  = map { $_ => 1 } @keysTmp, keys(%$myOsConf);
        my @scriptKeys = keys(%validKeys);

        foreach my $scriptKey (@scriptKeys) {
            my $interpreter;
            my $content     = '';
            my $myActionObj = $myOsConf->{$scriptKey};
            if ( defined($myActionObj) ) {
                if ( ref($myActionObj) eq 'HASH' ) {
                    $content     = $myActionObj->{script};
                    $interpreter = $myActionObj->{interpreter};
                }
                else {
                    &$logger("ERROR: $app action($scriptKey) defined not in json format: $myActionObj\n");
                }

                if ( not defined($interpreter) or $interpreter eq '' ) {
                    &$logger("ERROR: $app action($scriptKey) has no attribute:interpreter\n");
                }
            }

            if ( not defined($interpreter) or $interpreter eq '' ) {
                if ( $ostype eq 'windows' ) {
                    $interpreter = 'cmd';
                }
                else {
                    $interpreter = 'sh';
                }
            }

            #&$logger("DEBUG: CREATE $scriptKey  FILE START , conetnt is $content  \n");
            my $scriptDir = "$confDir/managed/$app";
            if ( not -e $scriptDir ) {
                mkdir($scriptDir);
            }
            else {
                foreach my $oldFile ( glob("$scriptDir/$scriptKey.*") ) {
                    unlink($oldFile);
                }
                if ( -e "$scriptDir/$scriptKey" ) {
                    unlink("$scriptDir/$scriptKey");
                }
            }

            my $extName = '';
            if ( $ostype eq 'windows' ) {
                $extName = $self->_getWinScriptExt($interpreter);
            }

            my $file = IO::File->new(">$scriptDir/$scriptKey$extName");
            if ( defined($file) ) {
                print $file ($content);
                $file->close();
            }

        }
    }

    foreach my $appDir ( glob("$confDir/managed/*") ) {
        my $appSubDir = basename($appDir);
        if ( $appSubDir ne '.' and $appSubDir ne '..' and -d $appDir ) {
            if ( not defined( $appsConf->{$appSubDir} ) ) {
                rmdir($appDir);
            }
        }
    }

    #&$logger("DEBUG: CREATE md5  FILE START , conetnt is $appsMd5  \n");
    my $md5File = IO::File->new(">$appsConfMd5File");
    if ( defined($md5File) ) {
        print $md5File ($appsMd5);
        $md5File->close();
    }
}

sub _updategroup {
    my ( $self, $cmdobj ) = @_;
    my $config = $self->{config}->{_};
    my $logger = $self->{logger};
    if ( $cmdobj->{'isNew'} eq '1' ) {
        $config->{'proxy.group'} = $cmdobj->{'groupinfo'};
        if ( not $self->{config}->write( $self->{confFile} ) ) {
            &$logger("WARN:  Update config file failed $!\n");
        }
    }
}

sub _healthCheck {
    my ( $self, $tagent ) = @_;
    my $config = $self->{config}->{_};
    my $logger = $self->{logger};

    my $ip   = '127.0.0.1';
    my $port = $config->{'listen.port'};

    my $authKeyEncrypted = $config->{'credential'};
    my $authKey          = $authKeyEncrypted;
    if ( $authKeyEncrypted =~ s/^{ENCRYPTED}\s*// ) {
        $authKey = _rc4_decrypt_hex( $self->{MY_KEY}, $authKeyEncrypted );
    }

    my $echoMsg = 'heartbeat';
    my $echoBack;

    $tagent->{password} = $authKey;

    eval { $echoBack = $tagent->echo($echoMsg); };

    if ( defined($echoBack) and $echoBack eq $echoMsg ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub handleCtlCmd {
    my ( $self, $socket, $cmd ) = @_;
    my $logger = $self->{logger};

    $cmd =~ s/^\s+|\s$//;
    if ( $cmd ne '' ) {
        my $cmdobj;
        eval { $cmdobj = from_json($cmd); };
        if ($@) {
            &$logger("ERROR: command from server not in json formant:$@\n$cmd\n");
            return;
        }

        &$logger( 'INFO: handle command:' . $cmdobj->{type} . "\n" );
        eval {
            if ( $cmdobj->{'type'} eq 'reload' ) {
                $self->_reload();
            }
            elsif ( $cmdobj->{'type'} eq 'resetcred' ) {
                $self->_resetCred();
            }

            #elsif ( $cmdobj->{'type'} eq 'upgrade' ) {
            #    $self->_upgrade();
            #}
            elsif ( $cmdobj->{'type'} eq 'updateAppsConf' ) {
                &$logger( 'INFO: update apps conf: ' . $cmdobj->{data} . "\n" );
                $self->_updateAppsConf( $cmdobj->{data} );
            }
            elsif ( $cmdobj->{'type'} eq 'moduleAction' ) {
                &$logger( 'INFO: execute module action: ' . $cmdobj->{moduleName} . '.' . $cmdobj->{moduleAction} . "\n" );
                $self->_execModuleAction( $cmdobj->{moduleName}, $cmdobj->{moduleAction} );
            }
            else {
                &$logger( 'INFO: command:' . $cmdobj->{type} . " not supported.\n" );
            }
        };
        if ($@) {
            &$logger( 'ERROR: handle action ' . $cmdobj->{'type'} . " failed, $@\n" );
        }
    }
}

sub getWinProcCpuAndMem {
    my ($self) = @_;
    my $wmi;

    my $pid;

    my $confBase = $ENV{TAGENT_HOME};
    my $progName = $FindBin::Script;
    my $pidFile  = "$confBase/logs/$progName.pid";

    my $pidFh;
    open( $pidFh, "<$pidFile" );
    if ( defined($pidFh) ) {
        my $allPid = <$pidFh>;
        close($pidFh);

        my @pids = split( /\s+/, $allPid );
        $pid = $pids[0];
    }

    eval( '
        use Win32::OLE;
    Win32::OLE->Option( Warn => 0 );
    $wmi = Win32::OLE->GetObject("winmgmts:{impersonationLevel=impersonate,(Debug)}!//./root/cimv2") || die ("get wmi object failed.");
        '
    );

    my $proc = $wmi->Get("Win32_Process=$pid");

    my $aCpuTime = $proc->{UserModeTime} + $proc->{KernelModeTime};
    sleep(1);
    $proc = $wmi->Get("Win32_Process=$pid");
    my $bCpuTime = $proc->{UserModeTime} + $proc->{KernelModeTime};

    my $cpuPercent = sprintf( '%.2f', ( $bCpuTime - $aCpuTime ) / $ENV{"NUMBER_OF_PROCESSORS"} / 10000000 * 100 );
    my $memSize    = sprintf( '%.2f', $proc->{WorkingSetSize} / 1024 / 1024 );

    return ( sprintf( '%.2f', $cpuPercent ), sprintf( '%.2f', $memSize ) );
}

sub getPosixProcCpuAndMem {
    my ($self)   = @_;
    my $logger   = $self->{logger};
    my $confBase = $ENV{TAGENT_HOME};
    my $progName = $FindBin::Script;
    my $pidFile  = "$confBase/logs/$progName.pid";
    my $pidFh;

    my $pcpu = 0;
    my $mem  = 0;

    open( $pidFh, "<$pidFile.subproc" );
    if ( defined($pidFh) ) {
        my $allPid = <$pidFh>;
        close($pidFh);

        if ( not defined($allPid) ) {
            $allPid = '';
        }

        my @pids = split( /\s+/, $allPid );
        push( @pids, $$ );

        foreach my $pid (@pids) {
            my $procInfo;
            my $cmd;
            if ( $self->{ostype} eq 'aix' ) {
                $cmd = "ps -p $pid -o pcpu,rssize |";
            }
            elsif ( $self->{ostype} eq 'hp-ux' ) {
                $cmd = "export UNIX95=1;ps -p $pid -o pcpu,sz |";
            }
            else {
                $cmd = "ps -p $pid -o pcpu,rss |";
            }

            if ( open( $procInfo, $cmd ) ) {
                my $line;
                $line = <$procInfo>;
                $line = <$procInfo>;
                $line =~ s/^\s+//;
                my ( $p, $m ) = split( /\s+/, $line );
                $pcpu = $pcpu + sprintf( '%.2f', $p );
                $mem  = $mem + sprintf( '%.2f', $m );
            }
            close($procInfo);
        }
    }
    if ( $self->{ostype} eq 'hp-ux' ) {
        my $pageSize = 4096;
        eval {
            my $cmd = "getconf PAGESIZE |";
            my $pageInfo;
            if ( open( $pageInfo, $cmd ) ) {
                $pageSize = <$pageInfo>;
            }
        };
        if ($@) {
            &$logger("WARN: get page size failed, set pageSize = 4096\n");
        }
        $mem = $pageSize * $mem / 1024;
    }

    return ( sprintf( '%.2f', $pcpu ), sprintf( '%.2f', $mem / 1024 ) );
}

sub initAppStatus {
    my ($self) = @_;
    my $appStatus = {};
    $appStatus->{status}           = '';
    $appStatus->{'mon-fail-count'} = 0;
    $appStatus->{'fail-run-count'} = 0;
    $appStatus->{'over-run-count'} = 0;

    return $appStatus;
}

sub runCmd {
    my $self = shift;

    my $ostype = $self->{ostype};

    my $pid;
    my $pipe;

    if ( $ostype eq 'windows' ) {
        $pid = open( $pipe, '-|', @_ );
    }
    else {
        $pid = open( $pipe, '-|', @_ );
    }

    return ( $pid, $pipe );
}

sub checkRule {
    my ( $self, $app, $appStatus ) = @_;
    my $logger      = $self->{logger};
    my $ostype      = $self->{ostype};
    my $appsConf    = $self->{appsConf};
    my $restartRule = $appsConf->{$app}->{$ostype}->{'restart-rule'};

    #&$logger("DEBUG: restart-rule:" . to_json($restartRule) . "\n");

    if ( not defined($restartRule) ) {
        return ( undef, undef );
    }

    my $needRestart   = 0;
    my $matchSchedule = 0;
    my $interval      = $self->{loopInterval};

    if ( int( $restartRule->{'when-over-run'} ) > 0 and $appStatus->{'over-run-count'} >= int( $restartRule->{'when-over-run'} ) ) {
        &$logger("WARN: $app continouse over-run count:$appStatus->{'over-run-count'}, try to restart.\n");
        $appStatus->{'over-run-count'} = 0;
        $needRestart = 1;
    }

    if ( $needRestart == 0 and int( $restartRule->{'when-fail-run'} ) > 0 and $appStatus->{'fail-run-count'} >= int( $restartRule->{'when-fail-run'} ) ) {
        &$logger("WARN: $app continouse fail-run count:$appStatus->{'fail-run-count'}, try to restart.\n");
        $appStatus->{'fail-run-count'} = 0;
        $needRestart = 1;
    }

    if ( $needRestart == 0 and $restartRule->{'when-down'} eq 'true' and $appStatus->{status} eq 'down' ) {
        &$logger("WARN: $app is down, try to restart.\n");
        $needRestart = 1;
    }

    if ( $needRestart == 0 ) {
        $matchSchedule = 1;

        my $monthDayMatched = 1;
        my $hourMatched     = 1;
        my $weekDayMatched  = 1;
        my $minuteMatched   = 1;

        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
        $year = $year + 1900;
        $mon  = $mon + 1;

        my $whenWeekDay = $restartRule->{'when-week-day'};
        if ( defined($whenWeekDay) ) {
            if ( $whenWeekDay ne '*' and $whenWeekDay !~ /^$wday|\s$wday\s|$wday$/ ) {
                $weekDayMatched = 0;
                $matchSchedule  = 0;
            }
        }

        if ( $matchSchedule == 1 ) {
            my $whenMonthDay = $restartRule->{'when-month-day'};
            if ( defined($whenMonthDay) ) {
                if ( $whenMonthDay ne '*' and $whenMonthDay !~ /^$mday|\s$mday\s|$mday$/ ) {
                    $monthDayMatched = 0;
                    $matchSchedule   = 0;
                }
            }
        }

        if ( $matchSchedule == 1 ) {
            my $whenHour = $restartRule->{'when-hour'};
            if ( defined($whenHour) ) {
                if ( $whenHour ne '*' and $whenHour !~ /^$hour|\s$hour\s|$hour$/ ) {
                    $hourMatched   = 0;
                    $matchSchedule = 0;
                }
            }
        }

        if ( $matchSchedule == 1 ) {
            my $whenMinute = $restartRule->{'when-minute'};
            if ( defined($whenMinute) ) {
                if ( $whenMinute ne '*' ) {
                    my @whenMinutes = split( /\s+/, $whenMinute );
                    foreach my $aMin (@whenMinutes) {
                        if ( int($aMin) - $interval < $min or int($aMin) + $interval > $min ) {
                            $minuteMatched = 0;
                            $matchSchedule = 0;
                        }
                    }
                }
            }
        }
    }

    if ( $matchSchedule == 1 ) {
        &$logger("INFO: $app match restart schedule, try to restart.\n");
    }

    if ( $needRestart == 1 or $matchSchedule == 1 ) {
        my $myAppConf = $appsConf->{$app}->{$ostype};
        my $stopConf  = $myAppConf->{stop};
        my $startConf = $myAppConf->{start};

        if ( not defined($stopConf) or not defined($startConf) ) {
            return ( undef, undef );
        }

        my $stopInterpreter = $stopConf->{interpreter};
        if ( $stopInterpreter eq '' ) {
            undef($stopInterpreter);
        }

        my $startInterpreter = $startConf->{interpreter};
        if ( $startInterpreter eq '' ) {
            undef($startInterpreter);
        }

        my $confDir = $self->{confDir};

        my $restartCmd;
        if ( $ostype eq 'windows' ) {
            if ( not defined($stopInterpreter) or $stopInterpreter =~ /^\s*cmd\s*$/ ) {
                $stopInterpreter = 'cmd /c';
            }
            if ( not defined($startInterpreter) or $startInterpreter =~ /^\s*cmd\s*$/ ) {
                $startInterpreter = 'cmd /c';
            }

            my $stopExtName  = $self->_getWinScriptExt($stopInterpreter);
            my $startExtName = $self->_getWinScriptExt($startInterpreter);

            my $winConfDir = $confDir;
            $winConfDir =~ s/\//\\/g;
            $restartCmd = "$stopInterpreter \"$confDir\\managed\\$app\\stop$stopExtName\" 2>&1 && $startInterpreter \"$confDir\\managed\\$app\\start$startExtName\" 2>&1";
        }
        else {
            if ( not defined($stopInterpreter) ) {
                $stopInterpreter = 'sh';
            }
            if ( not defined($startInterpreter) ) {
                $startInterpreter = 'sh';
            }

            $restartCmd = "$stopInterpreter '$confDir/managed/$app/stop' 2>&1 && $startInterpreter '$confDir/managed/$app/start' 2>&1";
        }

        &$logger("INFO: try to restart $app:$restartCmd\n");

        #my $pid = open( $pipe, "$restartCmd |" );
        my ( $pid, $pipe ) = $self->runCmd($restartCmd);

        return ( $pid, $pipe );
    }

    return ( undef, undef );
}

sub monOtherApps {
    my ($self) = @_;

    my $logger = $self->{logger};

    my $appsConfMd5 = $self->{appsConfMd5};
    my $confDir     = $self->{confDir};

    my $appsConf = $self->{appsConf};
    if ( not defined($appsConf) ) {
        $appsConf = {};
    }

    my $appsConfMd5File = "$confDir/managed/apps.json.md5";

    if ( -f $appsConfMd5File ) {
        my $appsConfFile = "$confDir/managed/apps.json";
        if ( -f $appsConfFile ) {
            eval {
                my $newestAppsConfMd5 = $self->getFileContent($appsConfMd5File);
                if ( $newestAppsConfMd5 ne $appsConfMd5 ) {
                    &$logger("INFO: apps config changed, try to reload...\n");
                    my $appsJson = $self->getFileContent($appsConfFile);
                    $appsConf = from_json($appsJson);
                    my $ostype = $self->{ostype};

                    foreach my $app ( keys(%$appsConf) ) {

                        my $appConf     = $appsConf->{$app};
                        my $defaultConf = $appConf->{default};
                        my $myOsConf    = $appConf->{$ostype};

                        if ( not defined($myOsConf) ) {
                            $appConf->{$ostype} = $defaultConf;
                        }
                        else {
                            foreach my $key ( keys(%$defaultConf) ) {
                                if ( not defined( $myOsConf->{$key} ) ) {
                                    $myOsConf->{$key} = $defaultConf->{$key};
                                }
                            }
                        }
                    }

                    $self->{appsConf}    = $appsConf;
                    $self->{appsConfMd5} = $newestAppsConfMd5;
                    &$logger("INFO: apps config changed, reloaded.\n");
                }
            };
            if ($@) {
                &$logger("WARN: parse json file:$appsConfFile failed.\n");
            }
        }
    }

    my @apps   = keys(%$appsConf);
    my $ostype = $self->{ostype};

    my $pid2App      = {};
    my $pid2Pipe     = {};
    my $allAppStatus = $self->{appsStatus};

    my $restartPid2Pipe = {};
    my $restartPid2App  = {};

    my $pidKilled = {};

    foreach my $app (@apps) {
        my $appConf = $appsConf->{$app};

        my $myAppConf = $appConf->{$ostype};
        my $monConf   = $myAppConf->{monitor};
        my $interpreter;
        if ( not defined($monConf) ) {
            next;
        }

        $interpreter = $monConf->{interpreter};
        if ( $interpreter eq '' ) {
            undef($interpreter);
        }

        my $monCmd;
        if ( $ostype eq 'windows' ) {
            if ( not defined($interpreter) or $interpreter =~ /^\s*cmd\s*$/ ) {
                $interpreter = 'cmd /c';
            }
            my $extName = $self->_getWinScriptExt($interpreter);
            $monCmd = "\"$confDir/managed/$app/monitor$extName\" 2>&1";
            $monCmd =~ s/\//\\/g;
            $monCmd = "$interpreter $monCmd";
        }
        else {
            if ( not defined($interpreter) ) {
                $interpreter = 'sh';
            }
            $monCmd = "$interpreter '$confDir/managed/$app/monitor' 2>&1";
        }

        #&$logger("DEBUG: mon cmd : $monCmd  \n");
        #my $pid = open( $pipe, "$monCmd |" );
        my ( $pid, $pipe ) = $self->runCmd($monCmd);

        if ( defined($pid) ) {
            $pid2App->{$pid}  = $app;
            $pid2Pipe->{$pid} = $pipe;
        }
    }

    my $startTime = time();

    while ( %$pid2App or %$restartPid2App ) {
        my $isTimeout = 0;
        my $timeOut   = 60;
        my $childPid;
        do {
            $childPid = waitpid( -1, WNOHANG );
            if ( $childPid > 0 ) {
                my $exitStatus = $?;

                my $pipe = $pid2Pipe->{$childPid};

                if ( not defined($pipe) ) {
                    my $restartPipe = $restartPid2Pipe->{$childPid};
                    my $restartApp  = $restartPid2App->{$childPid};

                    if ( defined($restartPipe) ) {
                        if ( $exitStatus == 0 ) {
                            &$logger("INFO: restart $restartApp success.");
                        }
                        else {
                            my $errMsg;
                            my $line;
                            while ( $line = <$restartPipe> ) {
                                $errMsg = $errMsg . $line;
                            }

                            if ( $isTimeout == 0 ) {
                                &$logger("ERROR: restart $restartApp failed:\n$errMsg");
                            }
                            else {
                                &$logger("ERROR: restart $restartApp time out:\n$errMsg");
                            }
                        }

                        close($restartPipe);
                        delete( $restartPid2Pipe->{$childPid} );
                        delete( $restartPid2App->{$childPid} );
                    }
                    next;
                }

                my $app       = $pid2App->{$childPid};
                my $appStatus = $allAppStatus->{$app};
                if ( not defined($appStatus) ) {
                    $appStatus = $self->initAppStatus();
                }

                my $line;
                my $errMsg = '';
                my $key;
                my $val;
                while ( $line = <$pipe> ) {
                    if ( $line =~ /\s*(\w+)\s*[=:]\s*([^\s]+)/ ) {
                        $key = $1;
                        $val = $2;
                        if ( $key eq 'status' ) {
                            if ( $val eq 'over-run' ) {
                                $appStatus->{'fail-run-count'} = 0;
                                if ( $appStatus->{status} eq 'over-run' ) {
                                    $appStatus->{'over-run-count'} = 1 + $appStatus->{'over-run-count'};
                                }
                                else {
                                    $appStatus->{'over-run-count'} = 1;
                                }
                            }
                            elsif ( $val eq 'fail-run' ) {
                                $appStatus->{'over-run-count'} = 0;
                                if ( $appStatus->{status} eq 'fail-run' ) {
                                    $appStatus->{'fail-run-count'} = 1 + $appStatus->{'fail-run-count'};
                                }
                                else {
                                    $appStatus->{'fail-run-count'} = 1;
                                }
                            }
                            else {
                                $appStatus->{'over-run-count'} = 0;
                                $appStatus->{'fail-run-count'} = 0;
                            }
                        }

                        $appStatus->{$key} = $val;
                    }
                    if ( $exitStatus != 0 ) {
                        $errMsg = $errMsg . $line;
                    }
                }

                if ( $exitStatus != 0 ) {
                    if ( $isTimeout == 0 ) {
                        &$logger("ERROR: execute mon for $app failed:\n$errMsg\n");
                    }
                    else {
                        &$logger("ERROR: execute mon for $app > $timeOut, time out.\n$errMsg\n");
                    }

                    if ( $appStatus->{status} eq 'mon-fail' ) {
                        $appStatus->{'mon-fail-count'} = 1 + $appStatus->{'mon-fail-count'};
                    }
                    else {
                        $appStatus->{'mon-fail-count'} = 1;
                    }
                    $appStatus->{status} = 'mon-fail';
                }
                else {
                    &$logger("INFO: execute mon for $app succeed.\n");
                    $appStatus->{'mon-fail-count'} = 0;
                }

                $allAppStatus->{$app} = $appStatus;

                close($pipe);
                delete( $pid2Pipe->{$childPid} );
                delete( $pid2App->{$childPid} );

                my ( $restartPid, $restartPipe ) = $self->checkRule( $app, $appStatus );
                if ( defined($restartPid) ) {
                    $restartPid2App->{$restartPid}  = $app;
                    $restartPid2Pipe->{$restartPid} = $restartPipe;
                }
            }
            else {
                if ( time() - $startTime > $timeOut ) {
                    $isTimeout = 1;
                }
                else {
                    sleep(1);
                }
            }

            if ( $isTimeout == 1 ) {
                my $timeOutPid;
                foreach $timeOutPid ( keys(%$pid2Pipe) ) {
                    if ( not defined( $pidKilled->{$timeOutPid} ) ) {
                        &$logger("WARN: timeout, kill pid:$timeOutPid.\n");
                        my $appStatus = $self->initAppStatus();
                        if ( $self->{ostype} eq 'windows' ) {
                            system("TASKKILL /F /T /PID $timeOutPid");
                        }
                        else {
                            kill( 'KILL', $timeOutPid );
                        }
                        $pidKilled->{$timeOutPid} = 1;
                    }
                }

                foreach $timeOutPid ( keys(%$restartPid2Pipe) ) {
                    if ( not defined( $pidKilled->{$timeOutPid} ) ) {
                        &$logger("WARN: timeout, kill pid:$timeOutPid.\n");
                        if ( $self->{ostype} eq 'windows' ) {
                            system("TASKKILL /F /T /PID $timeOutPid");
                        }
                        else {
                            kill( 'KILL', $timeOutPid );
                        }
                        $pidKilled->{$timeOutPid} = 1;
                    }
                }
            }
        } while ( $childPid != -1 );
    }

    return $allAppStatus;
}

sub mainLoop {
    my ($self)       = @_;
    my $conn         = $self->getConnection();
    my $logger       = $self->{logger};
    my $loopInterval = 0;

    my $config = Config::Tiny->read( $self->{confFile} );
    $self->{config} = $config;

    my $port = $config->{_}->{'listen.port'};

    my $ip = '127.0.0.1';

    my $authKeyEncrypted = $config->{_}->{'credential'};
    my $authKey          = $authKeyEncrypted;
    if ( $authKeyEncrypted =~ s/^{ENCRYPTED}\s*// ) {
        $authKey = _rc4_decrypt_hex( $self->{MY_KEY}, $authKeyEncrypted );
    }

    my $tagent = TagentClient->new( $ip, $port, $authKey );

    while (1) {
        my $config = Config::Tiny->read( $self->{confFile} );
        $self->{config} = $config;

        my $tenant       = $config->{_}->{'tenant'};
        my $agentId      = $config->{_}->{'tagent.id'};
        my $port         = $config->{_}->{'listen.port'};
        my $proxyGroup   = $config->{_}->{'proxy.group'};
        my $proxyGroupId = $config->{_}->{'proxy.group.id'};

        my ( $sel, $pcpu, $mem );

        if ( defined($conn) ) {
            $sel = new IO::Select($conn);
            if ( $sel->can_read($loopInterval) ) {
                my $cmd = readline($conn);

                if ( not defined($cmd) and $!{EINTR} ) {
                    next;
                }

                if ( not defined($cmd) ) {
                    &$logger( 'WARN: server connection ' . $self->{serverAddr} . " failed:$!\n" );
                    shutdown( $conn, 2 );
                    undef($conn);
                    $loopInterval = 3 + int( rand(7) );
                    sleep($loopInterval);

                    $conn = $self->getConnection();
                    next;
                }

                $self->handleCtlCmd( $conn, $cmd );
            }

            if ( $self->{ostype} eq 'windows' ) {
                ( $pcpu, $mem ) = $self->getWinProcCpuAndMem();
            }
            else {
                ( $pcpu, $mem ) = $self->getPosixProcCpuAndMem();
            }
        }
        else {
            sleep(10);
        }

        my $status      = 'working';
        my $isAgentWork = $self->_healthCheck($tagent);
        if ( $isAgentWork == 0 ) {
            $status = 'stuck';
            &$logger("ERROR: health check failed, try to reload.\n");
            $self->_reload();
        }

        if ( defined($conn) and defined($agentId) and $agentId ne '' ) {
            my $statusInfo = {};
            $statusInfo->{type}         = 'monitor';
            $statusInfo->{tenant}       = $tenant;
            $statusInfo->{agentId}      = int($agentId);
            $statusInfo->{port}         = int($port);
            $statusInfo->{ipString}     = collectIp();
            $statusInfo->{proxyGroup}   = $proxyGroup;
            $statusInfo->{proxyGroupId} = $proxyGroupId;
            $statusInfo->{proxyIp}      = $self->{proxyIp};
            $statusInfo->{proxyPort}    = $self->{proxyPort};
            $statusInfo->{pcpu}         = $pcpu * 1;
            $statusInfo->{mem}          = $mem * 1;
            $statusInfo->{status}       = $status;
            $statusInfo->{version}      = getVersion();

            eval {
                &$logger("INFO: begin to check managed app.\n");
                my $allAppStatus = $self->monOtherApps();
                &$logger("INFO: check managed app finished.\n");
                $statusInfo->{appsInfo} = $allAppStatus;
            };
            if ($@) {
                &$logger("ERROR: $@\n");
            }

            $conn->syswrite( to_json($statusInfo) . "\n" );
            &$logger( "INFO: Send heartbeat info:" . to_json($statusInfo) . "\n" );

            my $isFailed = 0;
            if ( $sel->can_read(60) ) {
                my $buf = readline($conn);
                &$logger("INFO: Recive server Response: $buf\n");

                if ( not defined($buf) ) {
                    $isFailed = 1;
                    &$logger( 'WARN: server connection' . $self->{serverAddr} . " failed:$!\n" );
                }
                else {
                    $loopInterval = $self->{loopInterval};
                    if ( $loopInterval <= 15 ) {
                        $loopInterval = 180;
                        $self->{loopInterval} = $loopInterval;
                    }

                    $buf =~ s/^\s+|\s+$//;
                    if ( $buf ne '' ) {
                        my $resp;
                        eval { $resp = from_json($buf); };

                        if ($@) {
                            &$logger("ERROR: server heartbeat response not in json format:$@\n$buf\n");
                        }
                        else {
                            if ( defined( $resp->{Status} ) and $resp->{Status} ne 'OK' ) {
                                $isFailed = 1;
                                &$logger("WARN: get server error:$buf\n");
                            }
                            if ( defined( $resp->{type} ) and $resp->{type} eq 'updategroup' ) {
                                my $configProxys = $config->{'proxy.group'};
                                my $respProxys   = $resp->{'groupinfo'};
                                if ( $configProxys ne $respProxys and $respProxys ne '' ) {

                                    #my @confProxyList = sort(split( /\s*,\s*/, $group ));
                                    #my @respProxyList = sort(split( /\s*,\s*/, $respProxys);
                                    &$logger("INFO: Update proxy group from:$configProxys to:$respProxys and reload.\n");
                                    $self->_updategroup($resp);
                                    shutdown( $conn, 2 );
                                    undef($conn);
                                    $conn = $self->getConnection();
                                }
                            }
                        }
                    }
                }
            }
            else {
                $isFailed = 1;
                &$logger("WARN: get server response failed.\n");
            }

            if ( $isFailed == 1 ) {
                shutdown( $conn, 2 );
                undef($conn);

                $loopInterval = 3 + int( rand(7) );
                sleep($loopInterval);
                $conn = $self->getConnection();
            }
        }
    }
}

1;

