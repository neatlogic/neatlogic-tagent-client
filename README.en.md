[中文](README.md) / English
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## About

Tagent is used for deployment on the client side, accomplishing complex operations that ssh and others cannot complete.

## Tagent User Guide

### Installation Packages

Linux｜Unix installation package: tagent_linux.tar
Windows installation package: tagent_windows_x32.tar, tagent_windows_x64.tar (Windows installation package includes Perl
runtime and 7z tool)

### Automatic Installation

#### Get install.sh or install.vbs(Windows) from the subdirectory bin

Automatic installation requires placing the Tagent installation package somewhere that can be downloaded via HTTP or
FTP.
The address and tenant name in the following installation sample scripts need to be modified according to actual
conditions.
Variable: RUNNER_ADDR is the URL of the execution node, choose based on whether the network can be connected. As long as
the network is accessible, choosing any RUNNER will have the same effect.
Tenant selection, input according to the tenant set by the system installation.

#### Linux|Unix

```shell
#Linux installation, run as root user
RUNNER_ADDR=http://10.68.10.60:8084
cd /tmp
curl -o install.sh $RUNNER_ADDR/autoexecrunner/tagent/download/install.sh
bash install.sh --listenaddr 0.0.0.0 --port 3939 --tenant develop --pkgurl $RUNNER_ADDR/autoexecrunner/tagent/download/tagent.tar --serveraddr $RUNNER_ADDR
```

```shell
#Linux installation, run as app user, listening on port 2020
RUNNER_ADDR=http://10.68.10.60:8084
cd /tmp
curl -o install.sh $RUNNER_ADDR/autoexecrunner/tagent/download/install.sh
bash install.sh --runuser app --listenaddr 0.0.0.0 --port 2020 --tenant develop --pkgurl $RUNNER_ADDR/autoexecrunner/tagent/download/tagent.tar --serveraddr $RUNNER_ADDR
```

#### Windows

```shell
#Open cmd.exec in Administrator mode
cd "%Temp%"
#use browser to download install.vbs to directory:%Temp%
#http://192.168.0.26:8080/download/tagent-bootstrap/install.vbs
set RUNNER_ADDR=http://10.68.10.60:8084
cscript install.vbs /tenant:develop /pkgurl:%RUNNER_ADDR%/autoexecrunner/tagent/download/tagent_windows_x64.tar /serveraddr:%RUNNER_ADDR% /listenaddr:0.0.0.0 /port:3939
```

### Manual Installation

#### Linux|Unix

Upload the installation package to the server and unzip it to /opt/tagent

```shell
RUNNER_ADDR=http://10.68.10.60:8084
mkdir /opt/tagent
tar -C /opt/tagent -xvf tagent.tar
cd /opt/tagent/bin
./setup.sh --action install --listenaddr 0.0.0.0 --port 3939 --tenant develop --server

addr $RUNNER_ADDR
```

#### Windows

Upload the installation package to the server and unzip it to c:/tagent

```shell
set RUNNER_ADDR=http://10.68.10.60:8084
mkdir c:\tagent
#unzip to c:/tagent
cd c:\tagent
service-install.bat %RUNNER_ADDR% develop 0.0.0.0 3939
```

### Manual Uninstallation

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
