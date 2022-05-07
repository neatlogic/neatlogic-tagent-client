#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

use strict;
use Getopt::Long;
use File::Basename;
use LogTailer;

sub usage {
    my $pname = $FindBin::Script;

    print("Usage: $pname --addr <url | host:port> [--timeout <seconds>] [--prescript <script to execute>] <log file pattern1> <log file pattern2> ...\n");
    print("       <url | host:port>: example: http://10.0.0.1:8080/test or 10.0.0.1:8080\n");
    print("       timeout:           timeout seconds\n");
    print("       prescript:         script to be execute before tail log\n");
    print("       log file pattern:  not or more log file patterns, wildcard is ok\n");

    exit(1);
}

sub main {
    my $rc = 0;

    my $pname = $FindBin::Script;

    my ( $addr, $timeout, $preScript, @logPatterns );
    $timeout = 300;

    GetOptions(
        'addr:s'    => \$addr,
        'timeout:i' => \$timeout,
        'prescript:s' => \$preScript,
        '<>'        => sub { my $item = shift(@_); push( @logPatterns, $item ); }
    );

    my $optError = 0;
    if ( not defined($addr) ) {
        $optError = 1;
        print("ERROR: option --addr not defined.\n");
        $rc = 1;
    }
    if ( scalar(@logPatterns) == 0 ) {
        $optError = 1;
        print("ERROR: there is no log pattern provided.\n");
        $rc = 1;
    }

    if ( $optError == 1 ) {
        usage();
    }

    my @serverLogInfos;
    foreach my $logPattern (@logPatterns) {
        my @logFiles = glob($logPattern);

        foreach my $logFile (@logFiles) {
            my $logInfo = {};
            $logInfo->{server} = '';
            $logInfo->{path} = $logFile;
            $logInfo->{name} = basename($logFile);
            $logInfo->{pos}  = undef;
            my $fh = IO::File->new("<$logFile");
            if ( defined($fh) ) {
                $fh->seek( 0, 2 );
                $logInfo->{pos} = $fh->tell();
                $fh->close();
            }

            push( @serverLogInfos, $logInfo );
        }
    }

    if ( defined($preScript) and $preScript ne '' ){
        print("INFO: execte script:$preScript\n");
        system($preScript);
    }

    my $isSuccess = 0;

    if ( $addr =~ /https?:\/\// ) {
        $isSuccess = LogTailer::checkUrlAvailable( $addr, 'GET', $timeout, \@serverLogInfos );
    }
    elsif ( $addr =~ /([\d\.\w\-]+):(\d+)/ ) {
        my $host = $1;
        my $port = int($2);
        $isSuccess = LogTailer::checkServiceAvailable( $host, $port, $timeout, \@serverLogInfos );
    }

    if ( $isSuccess ne 1 ) {
        $rc = 1;
    }

    return $rc;
}

exit main();

