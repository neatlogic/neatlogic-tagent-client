#!/usr/bin/perl
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

use strict;

package EnvExec;

use IO::File;
use POSIX qw(:sys_wait_h uname);

sub execEnvFile {
    my ($filePath) = @_;

    my @uname  = uname();
    my $ostype = $uname[0];

    my $fh = IO::File->new("<$filePath");

    if ( defined($fh) ) {
        my ( $line, $orgLine );
        my ( $name, $value );
        while ( $orgLine = $fh->getline() ) {
            $line = $orgLine;
            $line =~ s/^\s+|\s+$//;

            if ( $line =~ /^#/ ) {
                next;
            }

            $line =~ s/#.*//;
            $line =~ s/^\s*export\s+//;

            if ( $ostype =~ /Windows/i ) {
                $line =~ s/\//\\/g;
                $line =~ s/\$(\w+)/%$1%/g;
                $line =~ s/\$\{(\w+)\}/%$1%/g;
                $line =~ s/:/;/g;
                $line =~ s/^([a-zA-Z]);\\/$1:\\/;
                $line =~ s/;([a-zA-Z]);\\/;$1:\\/;
            }

            if ( $line =~ /^\s*(\w+?)\s*=\s*(.*?)\s*$/ ) {
                $name  = $1;
                $value = $2;
                if ( defined( $ENV{TAGENT_RELOAD} ) and ( index( $value, '$' . $name ) >= 0 or index( $value, "\${$name}" ) >= 0 ) ) {
                    next;
                }

                $value = `echo $value`;
                $value = '' if ( not defined $value );
                $value =~ s/\s+$//s;

                $ENV{$name} = $value;
            }
        }

        $fh->close();

        return 0;
    }
    else {
        return 1;
    }
}

#读取命令执行后管道的输出
sub getPipeOut {
    my ( $cmd, $timeOut ) = @_;
    my ( $line, @fileArray );

    my $pipe;
    my $pid = open( $pipe, "$cmd |" );
    if ( not defined($timeOut) ) {
        $timeOut = 30;
    }

    if ( defined($pipe) ) {
        local $SIG{ALRM} = sub {
            alarm(0);
            kill( 'KILL', $pid );
            die "ERROR: eval user profile with '$cmd' timeout($timeOut), failed.";
        };

        alarm($timeOut);

        while ( $line = <$pipe> ) {
            chomp($line);
            push( @fileArray, $line );
        }

        alarm(0);
        close($pipe);
    }

    return \@fileArray;
}

sub evalProfile {
    my ( $user, $config ) = @_;

    if ( not defined($user) ) {
        $user = '';
    }

    my $evalCmd;
    if ( $user eq '' ) {
        my @ent   = getpwuid($<);
        my $shell = $ent[8];
        $evalCmd = "echo env | $shell -l";
    }
    else {
        $evalCmd = "su - $user -c env";
    }

    if ( defined($config) ) {
        my $confEvalCmd = $config->{"profile.$user.eval.cmd"};
        if ( defined($confEvalCmd) and $confEvalCmd ne '' ) {
            $evalCmd = $confEvalCmd;
        }
        else {
            $confEvalCmd = $config->{"profile.eval.cmd"};
            if ( defined($confEvalCmd) and $confEvalCmd ne '' ) {
                $confEvalCmd =~ s/\$USER/$user/ig;
                $evalCmd = $confEvalCmd;
            }
        }
    }

    my $inheritVars = { 'PATH' => '', 'LD_LIBRARY_PATH' => '', 'LIBPATH' => '', 'PERL5LIB' => '', 'PERLLIB' => '' };

    my $timeOut = 30;
    $SIG{ALRM} = sub { die "eval user $user profile timeout($timeOut)." };
    alarm($timeOut);
    my $envLines = getPipeOut( $evalCmd, $timeOut );
    alarm(0);

    foreach my $line (@$envLines) {
        if ( $line =~ /^(\w+)=(.*)$/ ) {
            my $envName = $1;
            my $envVal  = $2;
            if ( exists( $inheritVars->{$envName} ) ) {
                my $oldVal = $ENV{$envName};
                if ( defined($oldVal) and $oldVal ne '' and index( $ENV{$envName}, $envVal ) < 0 ) {
                    $ENV{$envName} = $envVal . ':' . $ENV{$envName};
                }
                else {
                    $ENV{$envName} = $envVal;
                }
            }
            elsif ( $envName ne 'PWD' ) {
                $ENV{$envName} = $envVal;
            }
        }
    }
    $ENV{TERM} = 'dumb';
}

1;

