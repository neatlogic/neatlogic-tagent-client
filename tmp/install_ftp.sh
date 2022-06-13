#!/bin/sh

function ftpGetFile
{
echo "---------------start to ftp file to $ftpServer-------------------"
ftp -n<<!
open 20.0.39.29
user ftp_test ftp_test
binary
prompt off
lcd /opt
cd /tmp
bin
mget tagent_linux.tar.gz
close 
bye
!
}

#检查是否安装ftp
which ftp
if [ $? = 0 ]
then
	echo "INFO:ftp is ready"

	#下载压缩包  http  or 本地压缩包
	echo "INFO:ftp download install package from $pkgUrl....."
	cd /tmp
    ftpGetFile

	if [ $? != 0 ]
	then
		echo ERROR:download failed.
		exit -1;
	fi
fi

echo "INFO:Extract Package..."
cd /opt
gunzip tagent_linux.tar.gz
tar -xvf tagent_linux.tar
rm -rf tagent_linux.tar
cd /opt/tagent/bin/

echo "INFO:Execute setup.sh...."
sh setup.sh install


