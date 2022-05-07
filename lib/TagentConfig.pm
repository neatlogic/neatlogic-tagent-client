#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;

package TagentConfig;

no warnings;
use IO::File;
use Fcntl qw(:flock);
use Config::Tiny;
use Crypt::RC4;

my $MY_KEY = '#t#s=9^#0$1';

sub _rc4_encrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return join( '', unpack( 'H*', RC4( $key, $data ) ) );
}

sub _rc4_decrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return RC4( $key, pack( 'H*', $data ) );
}

sub _encryptPassword {
    my ( $confFilePath, $config ) = @_;
    my $gConfig = $config->{_};

    my $secretMap    = {};
    my $notEncrypted = 0;

    foreach my $key ( keys(%$gConfig) ) {
        if ( $key eq 'credential' or $key =~ /password$/i ) {
            my $orgVal = $gConfig->{$key};

            if ( $orgVal =~ /^\{ENCRYPTED\}\s*(.*?)\s*$/i ) {
                my $orgVal = $1;
                $secretMap->{$key} = _rc4_decrypt_hex( $MY_KEY, $orgVal );
            }
            else {
                $secretMap->{key} = $orgVal;
                my $newVal = '{ENCRYPTED}' . _rc4_encrypt_hex( $MY_KEY, $orgVal );
                $gConfig->{$key} = $newVal;
                $notEncrypted = 1;
            }
        }
    }
    if ( $notEncrypted == 1 ) {
        my $lockFh = IO::File->new("<$confFilePath");
        if ( defined($lockFh) ) {
            flock( $lockFh, LOCK_EX );
            $config->write($confFilePath);
            $lockFh->close();
        }
    }

    foreach my $key ( keys(%$secretMap) ) {
        $gConfig->{$key} = $secretMap->{$key};
    }
}

sub getConfig {
    my ($confFilePath) = @_;
    #my $homePath     = Cwd::abs_path("$FindBin::Bin/..");
    #my $confFilePath = "$homePath/conf/tsosi.conf";

    my $config = Config::Tiny->read($confFilePath);

    _encryptPassword( $confFilePath, $config );

    $config->{MY_KEY} = $MY_KEY;

    return $config;
}

1;
