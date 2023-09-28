中文 / [English](README.en.md)
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## 关于Neatlogic-Tagent
Neatlogic-Tagent用于部署在受管目标操作系统上，平滑替代主机连接协议一种可选方式，Tagent具备以下几点特点：
<ol>
<li>采用perl语言开发，运行环境依赖要求极低。</li>
<li>支持常见的Windows、Linux、SUSE、Aix等操作系统。</li>
<li>对操作系统资源极少，资源范围为：cpu <= 2%,内存：<= 200MB。</li>
<li>同一受管机器，支持多用户安装。</li>
<li>与<a href="../../../neatlogic-runner">Neatlogic-runner</a>建立心跳连接，定期探测目标环境和服务可用性。</li>
<li>支持从<a href="../../../neatlogic-runner">Neatlogic-runner</a>注册、管理、以及自动匹配管理网段下发执行。</li>
<li>支持在<a href="../../../neatlogic-web">Neatlogic-web</a>上查看日志、重启、修改配置、升级等操作。</li>
</ol>

## 适用场景 
Neatlogic-Tagent常见几种适用场景：
<ol>
<li>Windows类机器。</li>
<li>机器账号密码经常变更。</li>
<li>机器上多账号，不想在平台上维护不同用户密码。</li>
<li>深度使用自动化运维，如：资源安装交付。</li>
</ol>

## 如何获取安装包 
Neatlogic-Tagent两种获取安装包：
* [tagent](../../../tagent)获取各类型的安装包
```
#非windows
tagent.tar 
#windows 32位
tagent_windows_x32.zip
#windows 64位
tagent_windows_x64.zip
```

* 从<a href="../../../neatlogic-runner">Neatlogic-runner</a>获取安装包
```bash
#####安装包说明############
#Neatlogic-runner 自带3个安装包
#Unix类：tagent.tar
#Windows 32类：tagent_windows_x32.zip
#Windows 64类：tagent_windows_x64.zip
##########################
#eg:获取Unix安装包
#格式: http://Neatlogic-runner机器IP:8084/autoexecrunner/tagent/download/tagent.tar
# 示例
curl tagent.tar http://192.168.0.10:8084/autoexecrunner/tagent/download/tagent.tar

#eg: 获取Windows 64位安装包
# 示例
curl tagent_windows_x64.zip http://192.168.0.10:8084/autoexecrunner/tagent/download/tagent_windows_x64.zip
```

## 如何安装 
* Unix类操作系统建议以root用户安装，root安装的Agent会注册服务。
* Windows操作系统需以管理方式打开cmd窗口进行安装。
### 手动安装

* Linux | SUSE | Aix |Unix 类安装 
```bash 
# 登录目标受管机器，下载安装包,建议统一存放/opt目录
cd /opt
curl tagent.tar http://192.168.0.10:8084/autoexecrunner/tagent/download/tagent.tar

# 解压
tar -xvf tagent.tar

# 查看shell类型
echo $0 #aix操作系统需注意,大多数默认是ksh

# 执行安装
# 参数说明：--serveraddr neatlogic-runner的访问地址  --tenant 租户名称
# shell类型是bash，示例
sh tagent/bin/setup.sh --action install --serveraddr http://192.168.0.10:8084  --tenant demo

# shell类型是ksh，示例
sh tagent/bin/setup.ksh --action install --serveraddr http://192.168.0.10:8084  --tenant demo

# 安装完检查 (3个进程)
ps -ef |grep tagent 

# 查看日志
less tagent/run/root/logs/tagent.log 
# 查看配置 
less tagent/run/root/conf/tagent.conf

#启停
service tagent start/stop 
```

* Windows类型安装
<ol>
<li>查看Windows操作是多少位OS，选择对应安装包。</li>
<li>登录目标受管机器，下载安装包并拷贝到c盘,建议统一存放c盘根目录。</li>
<li>以管理员权限打开cmd窗口，并切换到c盘目录</li>
<li>cd tagent_windows_x64目录，执行：service-install.bat</li>
</ol>

示例：
```bat
cd c:\tagent_windows_x64
service-install.bat
```

### 自动安装

* Linux | SUSE | Aix |Unix 类安装示例

```shell
# 定义runner变量
RUNNER_ADDR=http://192.168.0.10:8084 #Neatlogic-runner的IP和端口
cd /opt
# 下载安装脚本
curl -o install.sh $RUNNER_ADDR/autoexecrunner/tagent/download/install.sh

# 执行安装
bash install.sh --tenant demo --pkgurl $RUNNER_ADDR/autoexecrunner/tagent/download/tagent.tar --serveraddr $RUNNER_ADDR
```

* Windows类安装示例
```powershell
# 打开浏览器输入runner地址下载install.vbs，如：http://192.168.0.10:8080/autoexecrunner/tagent/download/install.vbs
# 以管理员打开cmd窗口
# 切换install.vbs所在目录，或拷贝install.vbs到"%Temp%"目录
# 执行安装
set RUNNER_ADDR=http://192.168.0.10:8084
cscript install.vbs /tenant:demo /pkgurl:%RUNNER_ADDR%/autoexecrunner/tagent/download/tagent_windows_x64.tar /serveraddr:%RUNNER_ADDR% 
```

## 如何卸载
* Linux | SUSE | Aix |Unix 类服务卸载
```bash
cd /opt 

# 查看Shell类型
echo $0

# Shell为bash
sh tagent/bin/setup.sh --action uninstall

# Shell为ksh
sh tagent/bin/setup.ksh --action uninstall

# 删除安装目录
rm -rf tagent
```

* Windows类服务卸载

以管理员权限打开cmd窗口，切换到tagent_windows_x64安装目录，执行：service-uninstall.bat,并删除安装目录，示例：
```bat 
cd c:\tagent_windows_x64
service-uninstall.bat
rd /s /q c:\tagent_windows_x64
```


## 网络策略
<table style="width:100%">
    <tr>
        <th>源IP</th>
        <th>目的IP</th>
        <th>目的端口</th>
        <th>协议</th>
        <th>备注</th>
    </tr>
    <tr>
        <td>neatlogic-tagent-client主机</td>
        <td>neatlogic-runner主机</td>
        <td>8084/8888</td>
        <td>TCP</td>
        <td>
            8084注册端口/
            8888心跳端口
        </td>
    </tr>
    <tr>
        <td>neatlogic-runner主机</td>
        <td>neatlogic-tagent-client主机</td>
        <td>3939</td>
        <td>TCP</td>
        <td>命令下发端口</td>
    </tr>
</table>
