# Tagent使用说明
## 安装包
Linux｜Unix安装包：tagent_linux.tar
Windows安装包：tagent_windows_x32.tar、tagent_windows_x64.tar（windows安装包内嵌了Perl运行时和7z工具）

## 自动安装
### 获取子目录bin下的install.sh或者install.vbs(Windows)
自动安装需要在某个可以http或ftp下载的地方放置tagent的安装包

```shell
#Linux安装，以root用户运行
cd /tmp
curl -o install.sh http://myserver.com.cn/autoscripts/install.sh
bash install.sh --tenant develop --pkgurl http://192.168.0.26:8080/download/tagent-bootstrap/tagent_linux.tar --serveraddr http://192.168.1.140:8084
```

```shell
#Linux安装，以app用户运行，监听2020端口
cd /tmp
curl -o install.sh http://myserver.com.cn/autoscripts/install.sh
bash install.sh --user app --port 2020 --tenant develop --pkgurl http://192.168.0.26:8080/download/tagent-bootstrap/tagent_linux.tar --serveraddr http://192.168.1.140:8084
```

## 手动安装
### Linux|Unix
上传安装包到服务器，解压到/opt/tagent
```shell
cd /opt/tagent
./setup.sh --tenant develop --serveraddr http://192.168.1.140:8084
```

### Windows
上传安装包到服务器，解压到c:/tagent
```shell
cd c:\tagent
service-install.bat http://192.168.1.140:8084 develop
```
