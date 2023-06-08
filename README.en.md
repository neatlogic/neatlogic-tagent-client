[中文](README.md) / English
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## About

Neatlogic-Agent is an optional method for deploying on managed target operating systems, which smoothly replaces host connection protocols. Tagent has the following characteristics:

<ol>
<li>Developed using Perl language, with extremely low runtime dependency requirements</li>

<li>Support common operating systems such as Windows, Linux, SUSE, Aix, etc</li>

<li>There are very few operating system resources, with a resource range of CPU<=2% and memory<=200MB</li>

<li>The same managed machine supports multi user installation</li>

<li>Establish a heartbeat connection with <a href="../../../netlogic runner">Neatlogic runner</a>, regularly detect the target environment and service availability</li>

<li>Support registration, management, and automatic matching management of network segments for execution from <a href="../../../netlogic runner">Neatlogic runner</a></li>

<li>Support operations such as viewing logs, restarting, modifying configurations, and upgrading on <a href="../../../netlogic web">Neatlogic web</a></li>

</ol>

## Applicable scenarios 

There are several common application scenarios for Neatlogic Agent:

<ol>
<li>Windows class machines</li>

<li>Machine account passwords often change</li>

<li>Multiple accounts on the machine, do not want to maintain different user passwords on the platform</li>

<li>Deep use of automated operation and maintenance, such as resource installation and delivery</li>

</ol>

## How to obtain installation packages 

Neatlogic-Tagent There are two ways to obtain installation packages:

* be based on <a href="../../../neatlogic-tagent-client">Neatlogic-tagent-client</a> project packaging.

```
Explanation: The Windows installation package contains the Perl runtime dependency environment and 7z tools, as shown in the differences in the installation package below.
```

* be based on <a href="../../../neatlogic-runner">Neatlogic-runner</a>Obtain installation package.

```bash
#####Installation Package Description############
#Neatlogic runner comes with 3 installation packages
#Unix class: tagent.tar
#Windows 32 Class: agent_ Windows_ X32. zip
#Windows 64 class: agent_ Windows_ X64.zip
##########################

#Eg: Obtain Unix installation package
#Format: http://Neatlogic-runner Machine IP: 8084/autoexecutor/agent/download/agent.tar

#Example
curl tagent.tar http://192.168.0.10:8084/autoexecrunner/tagent/download/tagent.tar

#Eg: Obtain Windows 64 bit installation package
#Example
curl tagent_windows_x64.zip http://192.168.0.10:8084/autoexecrunner/tagent/download/tagent_windows_x64.zip
```

## How to install

* Unix operating systems are recommended to be installed as root users, and the agent installed by root will register the service.

* The Windows operating system needs to be installed by opening the cmd window in administrative mode.

### Manual install

* Linux | SUSE | Aix |Unix installation 
```bash 
# Login to the target managed machine and download the installation package. It is recommended to store it in the /opt directory uniformly

cd /opt
curl tagent.tar http://192.168.0.10:8084/autoexecrunner/tagent/download/tagent.tar

# decompression
tar -xvf tagent.tar

# View shell kind
echo $0 #The AIX operating system should be noted that most default is ksh

# Perform installation
# Parameter Description：--serveraddr neatlogic-runner http access address  --tenant tenant name
# shell kind is bash，eg
sh tagent/bin/setup.sh --action install --serveraddr http://192.168.0.10:8084  --tenant demo

# shell kind is ksh，eg
sh tagent/bin/setup.ksh --action install --serveraddr http://192.168.0.10:8084  --tenant demo

# Installation completion check (3 processes)
ps -ef |grep tagent 

# view log
less tagent/run/root/logs/tagent.log 

# view config
less tagent/run/root/conf/tagent.conf

#start / stop command
service tagent start/stop 
```

* Windows Installation

<ol>
<li>Check how many bits of OS the Windows operation is and select the corresponding installation package.</li>

<li>Login to the target managed machine, download the installation package, and copy it to the C drive. It is recommended to store it uniformly in the root directory of the C drive.</li>

<li>Open the cmd window with administrator privileges and switch to the c drive directory.</li>

<li>cd tagent_windows_x64 directory, execute:service-install.bat</li>

</ol>

Example：
```bat
cd c:\tagent_windows_x64
service-install.bat
```

### Automatic installation

* Linux | SUSE | Aix |Unix installation

```shell
# Define neatlogic-runner variable
RUNNER_ADDR=http://192.168.0.10:8084 #Neatlogic runner's IP and port
cd /opt
# Download installation script
curl -o install.sh $RUNNER_ADDR/autoexecrunner/tagent/download/install.sh

# Perform installation
bash install.sh --tenant demo --pkgurl $RUNNER_ADDR/autoexecrunner/tagent/download/tagent.tar --serveraddr $RUNNER_ADDR
```

* Windows installation
```powershell
#Open the browser and enter the neatlogic-runner address to download install.vbs, as shown in: http://192.168.0.10:8080/autoexecrunner/tagent/download/install.vbs

#Open cmd window as administrator

#Switch the directory where install.vbs is located, or copy install.vbs to the '% Temp%' directory

#Perform installation
set RUNNER_ADDR=http://192.168.0.10:8084
cscript install.vbs /tenant:demo /pkgurl:%RUNNER_ADDR%/autoexecrunner/tagent/download/tagent_windows_x64.tar /serveraddr:%RUNNER_ADDR% 
```

## How to uninstall

* Linux | SUSE | Aix |Unix uninstall
```bash
cd /opt 

# View shell kind
echo $0

# Shell kind is bash
sh tagent/bin/setup.sh --action uninstall

# Shell kind is ksh
sh tagent/bin/setup.ksh --action uninstall

# Remove installation directory
rm -rf tagent
```

* Windows uninstall

Open the cmd window with administrator privileges and switch to agent_ Windows_ X64 installation directory, execute: service uninstall.bat, and delete the installation directory. Example:

```bat 
cd c:\tagent_windows_x64
service-uninstall.bat
rd /s /q c:\tagent_windows_x64
```


## Network Policy

<table style="width:100%">
    <tr>
        <th>Source IP</th>
        <th>Destination IP</th>
        <th>Port</th>
        <th>Protocol</th>
        <th>Description</th>
    </tr>
    <tr>
        <td>neatlogic-tagent-client host</td>
        <td>neatlogic-runner host</td>
        <td>8084/8888</td>
        <td>TCP</td>
        <td>
            8084 registration port/
            8888 Heartbeat Port
        </td>
    </tr>
    <tr>
        <td>neatlogic-runner host</td>
        <td>neatlogic-tagent-client host</td>
        <td>3939</td>
        <td>TCP</td>
        <td>Command issue execution port</td>
    </tr>
</table>
