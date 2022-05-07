#!/bin/bash
PRE_CWD=`pwd`
PERL_MEDIA_HOME=$(dirname $0)

if [ ! "$#" = "1" ]
then
        echo "Usage: setup.sh <install_base>"
	echo "/opt/tagent/lib/perl-lib is prefer."
        exit -1
fi

install_base=$1

cd $PERL_MEDIA_HOME/perl-pkgs || exit 1;

for dir in `find . -maxdepth 1 -type d`
do
  if [ "$dir" != "." -a "$dir" != ".." ]
  then
    rm -rf $dir
  fi
done

for file in `find . -maxdepth 1 -type f`
do
	echo "untar $file"
        tar -xzvf $file
done


echo "Begin install perl pkgs......"
pwd

for dir in `find . -maxdepth 1 -type d`
do
        if [ -e "$dir/Build.PL" ]
        then
                cd $dir
                perl Build.PL --install_base $install_base
                #perl Build.PL --prefix $install_base
                ./Build install
                cd ..
        fi

        if [ -e "$dir/Makefile.PL" ]
        then
                cd $dir
                perl Makefile.PL INSTALL_BASE=$install_base
                #perl Makefile.PL PREFIX=$install_base
                make
                make install
                cd ..
        fi
done

cd $PRE_CWD

#oracle DBD
#perl Makefile.PL INSTALL_BASE=$TECHSURE_HOME/ezdeploy/lib/perl-lib -V 12.1.0 -h $ORACLE_HOME/sdk/include


