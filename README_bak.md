中文 / [English](README.en.md)
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## 关于

Tagent用于部署在客户端，实现ssh等无法完成的复杂操作。

## Tagent使用说明

### 安装包

Linux｜Unix安装包：tagent_linux.tar
Windows安装包：tagent_windows_x32.tar、tagent_windows_x64.tar（windows安装包内嵌了Perl运行时和7z工具）

### 自动安装

#### 获取子目录bin下的install.sh或者install.vbs(Windows)

自动安装需要在某个可以http或ftp下载的地方放置tagent的安装包
下面的安装样例脚本中的地址和租户名称需要根据实际情况进行修改
变量：RUNNER_ADDR 是执行节点的URL，根据网络是否能够连通来选择，只要网络能通，选择任意一个RUNNER效果是相同的。
tenant租户选择，根据系统安装设置的租户来进行输入。

#### Linux|Unix

```shell
#Linux安装，以root用户运行
RUNNER_ADDR=http://10.68.10.60:8084
cd /tmp
curl -o install.sh $RUNNER_ADDR/autoexecrunner/tagent/download/install.sh
bash install.sh --listenaddr 0.0.0.0 --port 3939 --tenant develop --pkgurl $RUNNER_ADDR/autoexecrunner/tagent/download/tagent.tar --serveraddr $RUNNER_ADDR
```

```shell
#Linux安装，以app用户运行，监听2020端口
RUNNER_ADDR=http://10.68.10.60:8084
cd /tmp
curl -o install.sh $RUNNER_ADDR/autoexecrunner/tagent/download/install.sh
bash install.sh --runuser app --listenaddr 0.0.0.0 --port 2020 --tenant develop --pkgurl $RUNNER_ADDR/autoexecrunner/tagent/download/tagent.tar --serveraddr $RUNNER_ADDR
```

#### Windows

```shell
#Open cmd.exec in Administrator mode
cd "%Temp%"
#use browser downlaod install.vbs to directory:%Temp%
#http://192.168.0.26:8080/download/tagent-bootstrap/install.vbs
set RUNNER_ADDR=http://10.68.10.60:8084
cscript install.vbs /tenant:develop /pkgurl:%RUNNER_ADDR%/autoexecrunner/tagent/download/tagent_windows_x64.tar /serveraddr:%RUNNER_ADDR% /listenaddr:0.0.0.0 /port:3939
```

### 手动安装

#### Linux|Unix

上传安装包到服务器，解压到/opt/tagent

```shell
RUNNER_ADDR=http://10.68.10.60:8084
mkdir /opt/tagent
tar -C /opt/tagent -xvf tagent.tar
cd /opt/tagent/bin
./setup.sh --action install --listenaddr 0.0.0.0 --port 3939 --tenant develop --serveraddr $RUNNER_ADDR
```

#### Windows

上传安装包到服务器，解压到c:/tagent

```shell
set RUNNER_ADDR=http://10.68.10.60:8084
mkdir c:\tagent
#解压到c:/tagent
cd c:\tagent
service-install.bat %RUNNER_ADDR% develop 0.0.0.0 3939
```

### 手动卸载

#### Linux|Unix

```shell
cd /opt/tagent/bin
bash setup.sh --action uninstall
cd /opt
rm -rf /opt/tagent
```

#### Windows

```shell
cd c:\tagent
service-uninstall.bat
rd /s /q c:\tagent
```
