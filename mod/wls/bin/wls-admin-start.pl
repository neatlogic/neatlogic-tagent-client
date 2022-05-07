#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use POSIX qw(uname);
use Utils;
use CommonConfig;
use WlsDeployer;
use File::Basename;

sub main {
    my $rc = 0;

    my @uname    = uname();
    my $ostype   = $uname[0];
    my $shellExt = 'sh';
    my $nullDev  = '/dev/null';

    if ( $ostype =~ /Windows/i ) {
        $ostype   = 'windows';
        $shellExt = 'cmd';
        $nullDev  = 'NUL';
    }
    else {
        $ostype   = 'unix';
        $shellExt = 'sh';
        $nullDev  = '/dev/null';
    }

    #set log file's default permission
    umask(0022);

    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR:use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];

    if ( scalar(@ARGV) > 2 ) {
        my $argsLen = scalar(@ARGV);
        my $i;
        for ( $i = 2 ; $i < $argsLen ; $i++ ) {
            my $envLine = $ARGV[$i];
            if ( $envLine =~ /\s*(\w+)\s*=\s*(.*)\s*$/ ) {
                $ENV{$1} = $2;
            }
        }
    }

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );
    my $adminServerName = $wlsDeployer->getAdminServerName();

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $wlsHome           = $config->{"wls_home"};
    my $javaHome          = $config->{"java_home"};
    my $domainDir         = $config->{"domain_home"};
    my $wlsUser           = $config->{"wls_user"};
    my $wlsPwd            = $config->{"wls_pwd"};
    my $userMemArgs       = $config->{"USER_MEM_ARGS"};
    my $javaExtOpts       = $config->{"JAVA_EXT_OPTS"};
    my $customStdoutFiles = $config->{"custom_stdoutfiles"};

    my $maxLogSize = $config->{"max_logsize"};
    if ( not defined($maxLogSize) or int($maxLogSize) == 0 ) {
        $maxLogSize = 2048;
    }

    my $maxLogFiles = $config->{"max_logfiles"};
    if ( not defined($maxLogFiles) or int($maxLogFiles) == 0 ) {
        $maxLogFiles = 123;
    }

    my $maxLogDays = $config->{"max_logdays"};
    if ( not defined($maxLogDays) or int($maxLogDays) == 0 ) {
        $maxLogDays = 93;
    }

    my $standalone = int( $config->{"standalone"} );
    my $adminUrl   = $config->{"admin_url"};
    $adminUrl =~ s/http/t3/i;

    my $appnames = $config->{"appname"};
    $appnames =~ s/\s*//g;
    my @appNames = split( ",", $appnames );

    my $appfiles = $config->{"appfile"};
    $appfiles =~ s/\s*//g;
    my @appFiles = split( ",", $appfiles );

    my $servernames = $config->{"servername"};
    $servernames =~ s/\s*//g;
    my @serverNames = split( ",", $servernames );

    my $startTimeout = $config->{'start_timeout'};
    if ( not defined($startTimeout) or $startTimeout eq '' ) {
        $startTimeout = 300;
    }

    my $timeout = int($startTimeout);

    if ( defined($domainDir) and $domainDir ne '' and defined($adminServerName) and $adminServerName ne '' ) {
        $ENV{MW_HOME}   = $wlsHome  if ( defined($wlsHome)  and $wlsHome ne '' );
        $ENV{JAVA_HOME} = $javaHome if ( defined($javaHome) and $javaHome ne '' );

        if ( $standalone == 1 ) {
            foreach my $appname (@appNames) {
                my $precheckUrl = $config->{"$appname.precheckurl"};
                if ( defined($precheckUrl) and $precheckUrl ne '' ) {
                    if ( not Utils::CheckUrlAvailable( $precheckUrl, "GET", $timeout ) ) {
                        print("ERROR: pre-check url $precheckUrl is not available in $timeout s, starting halt.\n");
                        exit(1);
                    }
                }
            }
        }

        my @serverLogInfos;

        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();

        #my $timeSpan = sprintf( "%04d%02d%02d_%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

        my $outDir = "$domainDir/servers/$adminServerName/logs";

        #my $outFile = "$outDir/$adminServerName.out.$timeSpan";
        my $outFile = "$outDir/$adminServerName.out";

        my @logFiles = ("$outDir/$adminServerName.log");

        if ( defined($customStdoutFiles) and $customStdoutFiles ne '' ) {
            my @outFiles = split( /\s*,\s*/, $customStdoutFiles );
            foreach my $customStdoutFile (@outFiles) {
                push( @logFiles, $customStdoutFile );
            }

            #$outFile = $outFiles[0] . ".$timeSpan";
            $outFile = $outFiles[0];
            print("INFO: Use custom log file:$outFile for log.\n");
        }

        push( @logFiles, $outFile );

        if ( not -e $outDir ) {
            mkdir($outDir);
        }

        foreach my $logFile (@logFiles) {
            my $logInfo = {};
            $logInfo->{server} = $adminServerName;
            $logInfo->{path}   = $logFile;
            $logInfo->{pos}    = undef;
            my $fh = IO::File->new("<$logFile");
            if ( defined($fh) ) {
                $fh->seek( 0, 2 );
                $logInfo->{pos} = -s $logFile;
                $fh->close();
            }
            push( @serverLogInfos, $logInfo );
        }

        $ENV{SERVER_NAME}      = $adminServerName;
        $ENV{TS_INSTANCE_NAME} = $adminServerName;
        if ( defined($userMemArgs) and $userMemArgs ne '' ) {
            $ENV{USER_MEM_ARGS} = $userMemArgs;
        }
        if ( defined($javaExtOpts) and $javaExtOpts ne '' ) {
            $ENV{JAVA_OPTIONS} = $javaExtOpts;
        }

        #$ENV{ADMIN_URL}        = $adminUrl;

        my $binPath = $FindBin::Bin;

        print("INFO: Try to start admin server in domain $domainDir, will log to $outFile.\n");

        if ( defined($wlsUser) and $wlsUser ne '' and defined($wlsPwd) and $wlsPwd ne '' ) {
            $ENV{WLS_USER} = $wlsUser;
            $ENV{WLS_PW}   = $wlsPwd;
        }

        my $cmd = "$domainDir/bin/startWebLogic.$shellExt";

        if ( $ostype eq 'windows' ) {
            $cmd = "\"$domainDir/bin/startWebLogic.$shellExt\"";
            $cmd = "start cmd /c \"$cmd 2>&1 | perl \"$binPath/logrotate\" --maxdays $maxLogDays --maxfiles $maxLogFiles --maxsize $maxLogSize \"$outFile\"\" && exit";
        }
        else {
            $cmd = "'$domainDir/bin/startWebLogic.$shellExt'";
            $cmd = "nohup $cmd 2>&1 | '$binPath/logrotate' --maxdays $maxLogDays --maxfiles $maxLogFiles --maxsize $maxLogSize '$outFile' &";
        }

        my $ret = system($cmd);

        if ( $ret != 0 ) {
            print("ERROR: Exec $cmd failed.\n");
            $rc = 2;
        }
        else {
            print("INFO: Exec $cmd succeed.\n");
        }

        if ( $standalone == 1 ) {
            foreach my $servername (@serverNames) {
                foreach my $appname (@appNames) {
                    my $checkUrl = $config->{"$servername.$appname.checkurl"};
                    if ( defined($checkUrl) and $checkUrl ne '' ) {
                        if ( Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout, \@serverLogInfos ) ) {
                            print("INFO: app $appname started.\n");
                        }
                        else {
                            print("ERROR: app $appname start failed.\n");
                            $rc = 2;
                        }
                    }
                }
            }
        }
        else {
            my $checkUrl = "$adminUrl/console";
            $checkUrl =~ s/^t3/http/i;
            if ( defined($checkUrl) and $checkUrl ne '' ) {
                if ( Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout, \@serverLogInfos ) ) {
                    print("INFO: admin $adminServerName started.\n");
                }
                else {
                    print("ERROR: admin $adminServerName start failed.\n");
                    $rc = 2;
                }
            }
        }

        if ( $ostype eq 'windows' ) {
            for ( my $i = 1 ; $i <= 3 ; $i++ ) {
                print("\x1b[[-=-exec finish-=-\x1b]]\r\n$rc\r\n");
                sleep(1);
            }
        }
    }
    else {
        print(" ERROR : no domain dir or server name found in the config file . \n ");
        $rc = 1;
    }

    return $rc;
}

exit main();

