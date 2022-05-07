@echo on
rem 指定FTP用户名
set ftpUser=ftp_test
rem 指定FTP密码
set ftpPass=ftp_test
rem 指定FTP服务器地址
set ftpIP=20.0.39.29
rem 指定待下载的文件位于FTP服务器的哪个目录
set ftpFolder=/tmp
rem 指定从FTP下载下来的文件存放到本机哪个目录
set LocalFolder=c:/


cd c:/
del 7za.dll
del 7zxa.dll
del 7za.exe
set ftpFile=%temp%/TempFTP.txt
>"%ftpFile%" (
  echo,%ftpUser%
  echo,%ftpPass%
  echo cd "%ftpFolder%"
  echo lcd "%LocalFolder%"
  echo bin
  echo mget tagent_windows_x64.zip
  echo mget 7za.dll
  echo mget 7za.exe
  echo mget 7zxa.dll
  echo bye
)
ftp -v -i -s:"%ftpFile%" %ftpIP%

# tagent 压缩包解压
echo "INFO:Extract Package"
cd c:/
7za.exe x tagent_windows_x64.zip
del tagent_windows_x64.zip
del 7za.dll
del 7zxa.dll
del 7za.exe
cd c:/tagent/

echo "run setup.sh"
./service-install.bat


