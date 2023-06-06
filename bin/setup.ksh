#!/bin/bash
usage() {
        pname=$(basename $0)
        echo "Usage:"
        echo "$pname --action {install|uninstall} --runuser USER_RunON --port ListenPort --registerurl REGISTER_URL --tenant Tenant"
        echo ""
        echo "--action: install|uninstall"
        echo "--runuser: User to run on, default:root"
        echo '--listenaddr: Agent listen ip, default:0.0.0.0'
        echo "--port: Agent listen port, default:3939"
        echo "--serveraddr: Agent register call back http addr(Runner http base url)"
        echo "  Example: http://192.168.0.88:8084"
        echo "--tenant: System teanant"
        echo ""
        echo "Example:$pname --action install --runuser root --port 3939 --tenant develop --serveraddr 'http://192.168.0.88:8084'"
        exit -1
}

parseOpts() {
	OPT_SPEC=":h-:"
	while getopts "$OPT_SPEC" optchar; do
                case "${optchar}" in
                -)
                        case "${OPTARG}" in
                        action)
                                ACTION=`eval echo \$"${OPTIND}"`
                                OPTIND=$(($OPTIND + 1))
                                ;;
                        runuser)
                                USER_RUNON=`eval echo \$"${OPTIND}"`
                                OPTIND=$(($OPTIND + 1))
                                ;;
                        listenaddr)
                                LISTEN_ADDR=`eval echo \$"${OPTIND}"`
                                OPTIND=$(($OPTIND + 1))
                                ;;
                        port)
                                PORT=`eval echo \$"${OPTIND}"`
                                OPTIND=$(($OPTIND + 1))
                                ;;
                        serveraddr)
                                SRV_ADDR=`eval echo \$"${OPTIND}"`
                                OPTIND=$(($OPTIND + 1))
                                ;;
                        tenant)
                                TENANT=`eval echo \$"${OPTIND}"`
                                OPTIND=$(($OPTIND + 1))
                                ;;
                        *)
                                if [ "$OPTERR" = 1 ] && [ "${OPT_SPEC:0:1}" != ":" ]; then
                                                echo "Unknown option --${OPTARG}" >&2
                                fi
                                ;;
                        esac
                        ;;
                h)
                        usage
                        exit 2
                        ;;
                *)
                        if [ "$OPTERR" != 1 ] || [ "${OPT_SPEC:0:1}" = ":" ]; then
                                        echo "Non-option argument: '-${OPTARG}'" >&2
                        fi
                        ;;
                esac
	done
}

parseOpts "$@"
echo "USER_RUNON:$USER_RUNON,action:$ACTION,listenaddr:$LISTEN_ADDR,port:$PORT,serveraddr:$SRV_ADDR,tenant:$TENANT \n"

if [ -z "$USER_RUNON" ]; then
        USER_RUNON="root"
fi

if [ -z "$LISTEN_ADDR" ]; then
        LISTEN_ADDR="0.0.0.0"
fi

if [ -z "$PORT" ]; then
        PORT="3939"
fi

if [ -z "$TENANT" ]; then
        TENANT="test"
fi

if [ -z "$ACTION" ]; then
        echo "ERROR: Option --action not defined."
        usage
fi

echo "USER_RUNON:$USER_RUNON,action:$ACTION,listenaddr:$LISTEN_ADDR,port:$PORT,serveraddr:$SRV_ADDR,tenant:$TENANT \n"

echo "INFO: $ACTION tagent on user $USER_RUNON."

CWD=$(cd $(dirname $0) && pwd)

TAGENT_BASE=$(cd $(dirname $0)/.. && pwd)
TAGENT_HOME=$TAGENT_BASE/run/$USER_RUNON
echo "TAGENT_BASE:$TAGENT_BASE."
#basePrefix=${TAGENT_BASE//\//\\\/}
#homePrefix=${TAGENT_HOME//\//\\\/}
basePrefix=$(echo $TAGENT_BASE | sed -e 's/\//\\\//g')
homePrefix=$(echo $TAGENT_HOME | sed -e 's/\//\\\//g')

chmod 755 $CWD/tagent.init.d

generate_user_conf() {
        if [ ! -z "$SRV_ADDR" ]; then
                #旧版本自动化
                #REG_URL="$SRV_ADDR/octopus-proxy/tagent/registerTagentInfoApi"
                #新版本自动化
                export REG_URL="$SRV_ADDR/autoexecrunner/public/api/rest/tagent/register?tenant=$TENANT"
                ####
                perl -i -pe 's/proxy\.registeraddress=.*/proxy.registeraddress=$ENV{REG_URL}/g' $TAGENT_BASE/conf/tagent.conf
        fi

        if [ ! -z "$TENANT" ]; then
                perl -i -pe "s/tenant=.*/tenant=$TENANT/g" $TAGENT_BASE/conf/tagent.conf
        fi

        if [ ! -e $TAGENT_BASE/run/$USER_RUNON ]; then
                mkdir $TAGENT_BASE/run/$USER_RUNON
                mkdir $TAGENT_BASE/run/$USER_RUNON/logs
                mkdir $TAGENT_BASE/run/$USER_RUNON/tmp
                cp -rf $TAGENT_BASE/conf $TAGENT_BASE/run/$USER_RUNON
                perl -i -pe "s/listen\.addr=.*/listen.addr=$LISTEN_ADDR/g" $TAGENT_BASE/run/$USER_RUNON/conf/tagent.conf
                perl -i -pe "s/listen\.port=.*/listen.port=$PORT/g" $TAGENT_BASE/run/$USER_RUNON/conf/tagent.conf
                chown -R $USER_RUNON $TAGENT_BASE/run/$USER_RUNON
        fi
}

clean_tagent_id() {
        if [ -e $TAGENT_BASE/run/$USER_RUNON ]; then
                perl -i -pe s/tagent\.id=.*/tagent.id=/ $TAGENT_BASE/run/$USER_RUNON/conf/tagent.conf
        fi
}

linux7_install() {
        svcRoot='/usr/lib/systemd/system'
        if [ ! -e "$svcRoot" ] && [ -e '/lib/systemd/system' ]; then
                svcRoot='/lib/systemd/system'
        fi

        if [ "$USER_RUNON" = "root" ]; then
                cp $CWD/tagent.service $svcRoot/tagent.service
                perl -i -pe "s/TAGENT_BASE/$basePrefix/g" $svcRoot/tagent.service
                perl -i -pe "s/TAGENT_HOME/$homePrefix/g" $svcRoot/tagent.service
                perl -i -pe "s/SUDO//g" $svcRoot/tagent.service
                systemctl daemon-reload
                systemctl enable tagent.service
                systemctl start tagent.service

                echo "Service tagent installed."
        else
                cp $CWD/tagent.service $svcRoot/tagent-$USER_RUNON.service
                perl -i -pe "s/TAGENT_BASE/$basePrefix/g" $svcRoot/tagent-$USER_RUNON.service
                perl -i -pe "s/TAGENT_HOME/$homePrefix/g" $svcRoot/tagent-$USER_RUNON.service
                perl -i -pe "s/SUDO/$USER_RUNON/g" $svcRoot/tagent-$USER_RUNON.service
                systemctl daemon-reload
                systemctl enable tagent-$USER_RUNON.service
                systemctl start tagent-$USER_RUNON.service

                echo "Service tagent-$USER_RUNON installed."
        fi
}

linux_install() {
        if [ "$USER_RUNON" = "root" ]; then
                cp $CWD/tagent.init.d /etc/init.d/tagent
                perl -i -pe "s/^\s*RUN_USER=/RUN_USER=root/" /etc/init.d/tagent
                perl -i -pe "s/^\s*TAGENT_BASE=/TAGENT_BASE=$basePrefix/" /etc/init.d/tagent
                chmod 755 /etc/init.d/tagent
                chkconfig --add tagent
                chkconfig --level=3 tagent on
                chkconfig --level=4 tagent on
                chkconfig --level=5 tagent on

                service tagent start
                echo "Service tagent installed."
        else
                cp $CWD/tagent.init.d /etc/init.d/tagent-$USER_RUNON
                perl -i -pe "s/^\s*RUN_USER=/RUN_USER=$USER_RUNON/" /etc/init.d/tagent-$USER_RUNON
                perl -i -pe "s/^\s*TAGENT_BASE=/TAGENT_BASE=$basePrefix/" /etc/init.d/tagent-$USER_RUNON
                chmod 755 /etc/init.d/tagent-$USER_RUNON
                chkconfig --add tagent-$USER_RUNON
                chkconfig --level=3 tagent-$USER_RUNON on
                chkconfig --level=4 tagent-$USER_RUNON on
                chkconfig --level=5 tagent-$USER_RUNON on

                service tagent-$USER_RUNON start
                echo "Service tagent-$USER_RUNON installed."
        fi
}

aix_install() {
        if [ "$USER_RUNON" = "root" ]; then
                #add entry tagent to /etc/inittab
                mkitab "tagent:2:wait:$TAGENT_BASE/bin/tagent start $TAGENT_HOME > /dev/console 2>&1"
                $TAGENT_BASE/bin/tagent start $TAGENT_HOME
                echo "Service tagent installed."
        else
                #add entry tagent-$USER_RUNON to /etc/inittab
                mkitab "tagent-$USER_RUNON:2:wait:sudo -u $USER_RUNON $TAGENT_BASE/bin/tagent start $TAGENT_HOME > /dev/console 2>&1"
                sudo -u $USER_RUNON $TAGENT_BASE/bin/tagent start $TAGENT_HOME

                echo "Service tagent-$USER_RUNON installed."
        fi
}

sunos_install() {
        if [ "$USER_RUNON" = "root" ]; then
                #generate tagent.xml in /lib/svc/manifest/site/tagent.xml
                svcbundle -i -s service-name=application/tagent \
                        -s start-method="$TAGENT_BASE/bin/tagent start $TAGENT_HOME" \
                        -s stop-method="$TAGENT_BASE/bin/tagent stop $TAGENT_HOME"
                #start the service, must use option '-t', disable without option '-t' will disable the service permently
                svcadm enable -t application/tagent

                echo "Service tagent-root installed."
        else
                #generate tagent-$USER_RUNON.xml in /lib/svc/manifest/site/tagent-$USER_RUNON.xml
                svcbundle -i -s service-name=application/tagent-$USER_RUNON \
                        -s start-method="sudo -u $USER_RUNON $TAGENT_BASE/bin/tagent start $TAGENT_HOME" \
                        -s stop-method="sudo -u $USER_RUNON $TAGENT_BASE/bin/tagent stop $TAGENT_HOME"
                #start the service, must use option '-t', disable without option '-t' will disable the service permently
                svcadm enable -t application/tagent-$USER_RUNON

                echo "Service tagent-$USER_RUNON installed."
        fi
}

linux7_uninstall() {
        svcRoot='/usr/lib/systemd/system'
        if [ ! -e "$svcRoot" ] && [ -e '/lib/systemd/system' ]; then
                svcRoot='/lib/systemd/system'
        fi

        if [ "$USER_RUNON" = "root" ]; then
                systemctl stop tagent
                systemctl disable tagent.service
                rm $svcRoot/tagent.service
                systemctl daemon-reload
                echo "Service tagent uninstalled."
                systemctl list-unit-files | grep tagent
        else
                systemctl stop tagent-$USER_RUNON
                systemctl disable tagent-$USER_RUNON.service
                rm $svcRoot/tagent-$USER_RUNON.service
                systemctl daemon-reload
                echo "Service tagent uninstalled."
                systemctl list-unit-files | grep tagent-$USER_RUNON
        fi
}

linux_uninstall() {
        if [ "$USER_RUNON" = "root" ]; then
                service tagent stop
                chkconfig --del tagent
                rm /etc/init.d/tagent
                echo "Service tagent uninstalled."
                chkconfig --list | grep tagent
        else
                service tagent-$USER_RUNON stop
                chkconfig --del tagent-$USER_RUNON
                rm /etc/init.d/tagent-$USER_RUNON
                echo "Service tagent-$USER_RUNON uninstalled."
                chkconfig --list | grep tagent-$USER_RUNON
        fi
}

aix_uninstall() {
        if [ "$USER_RUNON" = "root" ]; then
                $TAGENT_BASE/bin/tagent stop $TAGENT_HOME
                #remove entry tagent in /etc/inittab
                rmitab "tagent"
                echo "Service tagent uninstalled."
        else
                sudo -u $USER_RUNON $TAGENT_BASE/bin/tagent stop $TAGENT_HOME
                #remove entry tagent-$USER_RUNON in /etc/inittab
                rmitab "tagent-$USER_RUNON"
                echo "Service tagent-$USER_RUNON uninstalled."
        fi
}

sunos_uninstall() {
        if [ "$USER_RUNON" = "root" ]; then
                #disable tagent service permently
                svcadm disable application/tagent
                rm /lib/svc/manifest/site/tagent.xml
                svcadm restart manifest-import
                echo "Service tagent uninstalled."
        else
                #disable tagent-$USER_RUNON service permently
                svcadm disable application/tagent-$USER_RUNON
                rm /lib/svc/manifest/site/tagent-$USER_RUNON.xml
                svcadm restart manifest-import
        fi
        echo "Service tagent-$USER_RUNON uninstalled."
}

kernel=$(uname -s 2>&1)

if [ "$ACTION" = "uninstall" ]; then
        case "$kernel" in
        Linux)
                #initType=`pidof systemd && echo "systemd" || echo "sysvinit"`
                #pidof systemd > /dev/null && initType="systemd" || initType="sysvinit"
                ps -p1 | grep systemd >/dev/null && initType="systemd" || initType="sysvinit"
                if [ "$initType" = "sysvinit" ]; then
                        linux_uninstall
                else
                        linux7_uninstall
                fi
                ;;
        FreeBSD)
                linux_uninstall
                ;;
        AIX)
                aix_uninstall
                ;;
        SunOs)
                sunos_uninstall
                ;;
        *)
                echo $"Uninstall service on $kernel not support yet."
                exit 2
                ;;
        esac

        clean_tagent_id
else
        generate_user_conf

        case "$kernel" in
        Linux)
                #initType=`pidof systemd && echo "systemd" || echo "sysvinit"`
                #pidof systemd > /dev/null && initType="systemd" || initType="sysvinit"
                ps -p1 | grep systemd >/dev/null && initType="systemd" || initType="sysvinit"
                if [ "$initType" = "sysvinit" ]; then
                        linux_install
                else
                        linux7_install
                fi
                ;;
        FreeBSD)
                linux_install
                ;;
        AIX)
                aix_install
                ;;
        SunOS)
                sunos_install
                ;;
        *)
                echo $"Install service on $kernel not support yet."
                exit 2
                ;;
        esac
fi
