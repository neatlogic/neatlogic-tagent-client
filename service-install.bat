echo off
set SRV_ADDR=%1
set TENANT=%2
set LISTEN_ADDR=%3
set PORT=%4

IF NOT "%TENANT%" == "" (
    "%CD%\Perl\bin\perl" -i.bak -pe "s/tenant=.*/tenant=%TENANT%/g" "%CD%\conf\tagent.conf"
) 

IF NOT "%LISTEN_ADDR%" == "" (
    "%CD%\Perl\bin\perl" -i.bak -pe "s/listen.addr=.*/listen.addr=%LISTEN_ADDR%/g" "%CD%\conf\tagent.conf"
) 

IF NOT "%PORT%" == "" (
    "%CD%\Perl\bin\perl" -i.bak -pe "s/listen.port=.*/listen.port=%PORT%/g" "%CD%\conf\tagent.conf"
) 

IF NOT "%SRV_ADDR%" == "" (
    set REG_URL=%SRV_ADDR%/autoexecrunner/public/api/rest/tagent/register?tenant=%TENANT%
    "%CD%\Perl\bin\perl" -i.bak -pe "s/proxy\.registeraddress=.*/proxy.registeraddress=$ENV{REG_URL}/g" "%CD%\conf\tagent.conf"
)

echo on

@REM 请使用管理员运行cmd，运行此脚本进行服务安装
tssm install Tagent-Server "%CD%\Perl\bin\perl" tagent start
tssm set Tagent-Server DisplayName "Tagent-Server for automation"
tssm set Tagent-Server AppDirectory "%CD%\bin"
tssm set Tagent-Server AppEnvironmentExtra Path="%CD%"\Perl\bin;%%path%% PERLLIB="%CD%"\Perl\lib;"%CD%"\Perl\vender\lib;"%CD%"\Perl\site\lib PERL5LIB="%CD%"\Perl\lib;"%CD%"\Perl\vender\lib;"%CD%"\Perl\site\lib

tssm set Tagent-Server ObjectName LocalSystem
tssm set Tagent-Server Type SERVICE_WIN32_OWN_PROCESS

tssm set Tagent-Server AppThrottle 3000
tssm set Tagent-Server AppExit Default Restart
tssm set Tagent-Server AppRestartDelay 3000

@REM tssm set Tagent-Server AppStdout "%CD%\logs\service-out.log"
@REM tssm set Tagent-Server AppStderr "%CD%\logs\service-err.log"

@REM tssm set Tagent-Server AppStdoutCreationDisposition 4
@REM tssm set Tagent-Server AppStderrCreationDisposition 4
@REM tssm set Tagent-Server AppRotateFiles 1
@REM tssm set Tagent-Server AppRotateOnline 1
@REM tssm set Tagent-Server AppRotateSeconds 86400
@REM tssm set Tagent-Server AppRotateBytes 4194304

net start Tagent-Server
