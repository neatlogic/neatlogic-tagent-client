#!/bin/bash 

pkgUrl=$1
runUser=$2

if [ $# -lt 1 ]
then
	echo "Usage install.sh <pkgUrl> [userRunOn]"
	echo "Example:./install.sh root http://abc.com/service/tagent.tar root"
	exit -1
fi


if [ $# -lt 2 ]
then
	runUser=root
fi

#是否安装perl
echo "check perl environment"
which perl
if [ $? != 0 ]
	echo ERROR: perl not detect, tagent run on perl, install failed, exit.
	exit -1;
then
fi


#检查是否安装curl
which curl
if [ $? = 0 ]
then
	echo "INFO:curl is ready"

	#下载压缩包  http  or 本地压缩包
	echo "INFO:curl download install package from $pkgUrl....."
	curl -o /tmp/tagent.tar $pkgUrl

	if [ $? != 0 ]
	then
		echo ERROR:download failed.
		exit -1;
	fi
else
	which wget
	if [ $? = 0 ]
	then
                echo "INFO:wget download install package from $pkgUrl....."
		wget -O /tmp/tagent.tar $pkgUrl

		if [ $? != 0 ]
		then
			echo ERROR:download failed.
			exit -1;
		fi
	else
		echo ERROR: can not find curl or wget to download install package, install failed.
	fi
fi

# tagent 压缩包解压
echo "INFO:Extract Package"
tar xvf /tmp/tagent.tar  -C $installPath 

cd $installPath/bin/

echo "run setup.sh"
./setup.sh install $runUser

