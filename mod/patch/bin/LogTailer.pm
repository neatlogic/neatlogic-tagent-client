#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

package LogTailer;

use strict;
use File::Copy;
use File::Path;
use File::Basename;
use IO::File;
use Cwd;
use IO::Socket::INET;
use HTTP::Tiny;

sub _tailLog {
    my ( $serverName, $logFile, $pos, $logName ) = @_;

    my $fh     = IO::File->new("<$logFile");
    my $newPos = 0;
    my $line;

    if ( defined($fh) ) {
        $fh->seek( 0, 2 );
        my $endPos = $fh->tell();

        if ( not defined($pos) ) {
            $pos = $endPos;
        }

        if ( $pos > $endPos ) {
            $fh->seek( 0, 0 );
        }
        else {
            $fh->seek( $pos, 0 );
        }

        do {
            $line = $fh->getline();
            print( $logName, ':', $line );
        } while ( defined($line) );

        $newPos = $fh->tell();
        $fh->close();
    }
    else {
        return -1;
    }

    return $newPos;
}

sub _checkUrl {
    my ( $url, $method, $timeout ) = @_;
    my $isSuccess = 0;

    if ( not defined($method) or $method eq '' ) {
        $method = 'GET';
    }
    if ( not defined($timeout) or $timeout eq '' ) {
        $timeout = 300;
    }
    if ( not defined($url) or $url eq '' ) {
        print("ERROR: URL not defined.\n");
        return 0;
    }

    eval {
        my $statusCode = 500;

        my $http = HTTP::Tiny->new();
        my $response = $http->request( 'GET', $url );
        $statusCode = $response->{status};

        print("INFO:URL checking URL:$url, status code $statusCode\n");
        if ( $statusCode == 200 or $statusCode == 302 ) {
            print("INFO:URL checking URL:$url, status code $statusCode, started.\n");
            $isSuccess = 1;
        }
    };
    if ($@) {
        print("ERROR:$@\n");
    }

    return $isSuccess;
}

sub _checkTcp {
    my ( $host, $port, $timeout ) = @_;

    my $isSuccess = 0;

    eval {
        my $socket = IO::Socket::INET->new(
            PeerHost => $host,
            PeerPort => $port,
            Timeout  => $timeout
        );

        if ( defined($socket) ) {
            $isSuccess = 1;
            $socket->close();
        }

    };
    if ($@) {
        print("ERROR:$@\n");
    }

    return $isSuccess;
}

sub checkUrlAvailable {
    my ( $url, $method, $timeout, $logInfos ) = @_;

    foreach my $logInfo (@$logInfos) {
        $logInfo->{pos} = _tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos}, $logInfo->{name} );
    }

    my $isSuccess = 0;
    my $step      = 3;
    my $stepCount = $timeout / $step;
    for ( my $i = 0 ; $i < $stepCount ; $i++ ) {
        print("INFO:waiting service to start....\n");
        if ( _checkUrl( $url, $method, $timeout ) == 1 ) {
            $isSuccess = 1;
        }

        foreach my $logInfo (@$logInfos) {
            $logInfo->{pos} = _tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos}, $logInfo->{name} );
        }

        if ( $isSuccess == 1 ) {
            last;
        }

        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        print("WARN:service $url check failed.");
    }
    else {
        print("INFO: service $url started.\n");
    }

    return $isSuccess;
}

sub checkServiceAvailable {
    my ( $host, $port, $timeout, $logInfos ) = @_;

    foreach my $logInfo (@$logInfos) {
        $logInfo->{pos} = _tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos}, $logInfo->{name} );
    }

    my $isSuccess = 0;
    my $step      = 3;
    my $stepCount = $timeout / $step;
    for ( my $i = 0 ; $i < $stepCount ; $i++ ) {
        print("INFO:waiting service to start....\n");
        if ( _checkTcp( $host, $port, $timeout ) == 1 ) {
            $isSuccess = 1;
        }

        foreach my $logInfo (@$logInfos) {
            $logInfo->{pos} = _tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos}, $logInfo->{name} );
        }

        if ( $isSuccess == 1 ) {
            last;
        }

        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        print("WARN:service $host:$port check failed.");
    }
    else {
        print("INFO: service $host:$port started.\n");
    }

    return $isSuccess;
}

1;

