#!/usr/bin/perl
use strict;
use IO::File;
use FindBin;
use lib "$FindBin::Bin";
use Cwd 'abs_path';
use File::Copy;
use File::Path;
use POSIX;
use CommonConfig;
use Patcher;

my $homePath = abs_path("$FindBin::Bin/..");
my $progName = $FindBin::Script;
my @uname    = uname();
my $osType   = 'unix';
$osType = 'windows' if ( $uname[0] =~ /Windows/i );

sub usage {
    print("Usage:$progName <instance name> <version>\n");
    exit(-1);
}

sub main {
    my $ins     = $ARGV[0];
    my $version = $ARGV[1];

    if ( $osType eq 'windows' ) {
        $ENV{PATH} = "$homePath/../7-Zip;$ENV{ProgramFiles}/7-Zip;" . $ENV{PATH};
    }

    my $args = scalar(@ARGV);
    usage() if ( $args != 2 );

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

    my $patcher = Patcher->new( $homePath, $backupDir, $backupCount );

    my $status = 0;

    $status = $patcher->rollback( $ins, $version );

    exit($status);
}

main();

