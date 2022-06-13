#!/bin/sh

runUser=root
action=install

if [ $# -gt 0 ]; then
        action=$1
        runUser=$2
else
        echo "Usagen: tagent install|uninstall [User Run on] [port] [Register Url]"
        exit -1
fi

port=3939
if [ $# -gt 2 ]; then
        port=$3
fi

registerUrl=""
if [ $# -gt 3 ]; then
        registerUrl=$4
fi

if [ "$runUser" = "" ]; then
        runUser=root
fi

if [ "$action" = "help" ]; then
        echo "Usagen: setup.sh [install|uninstall] [user name]"
        echo "	example:setup.sh install root 3939"
        echo "	example:setup.sh uninstall root"
        echo "	example:setup.sh install app 4949"
        echo "	example:setup.sh uninstall app"
        exit 0
fi

echo "INFO:$action tagent on user $runUser."

CWD=$(
        cd $(dirname $0)
        pwd
)

TAGENT_BASE=$(
        cd $(dirname $0)/..
        pwd
)
TAGENT_HOME=$TAGENT_BASE/run/$runUser
echo "TAGENT_BASE:$TAGENT_BASE."
#basePrefix=${TAGENT_BASE//\//\\\/}
#homePrefix=${TAGENT_HOME//\//\\\/}
basePrefix=$(echo $TAGENT_BASE | sed -e 's/\//\\\//g')
homePrefix=$(echo $TAGENT_HOME | sed -e 's/\//\\\//g')

chmod 755 $CWD/tagent.init.d

generate_user_conf() {
        if [ ! -z "$registerUrl"]; then
                REG_URL=$registerUrl
                perl -i -pe "s/proxy\.registeraddress=.*/proxy.registeraddress=$ENV{REG_URL}/" $TAGENT_BASE/conf/tagent.conf
        fi

        if [ ! -e $TAGENT_BASE/run/$runUser ]; then
                mkdir $TAGENT_BASE/run/$runUser
                mkdir $TAGENT_BASE/run/$runUser/logs
                mkdir $TAGENT_BASE/run/$runUser/tmp
                cp -rf $TAGENT_BASE/conf $TAGENT_BASE/run/$runUser
                perl -i -pe "s/listen\.port=.*/listen.port=$port/g" $TAGENT_BASE/run/$runUser/conf/tagent.conf
                chown -R $runUser $TAGENT_BASE/run/$runUser
        fi
}

clean_tagent_id() {
        if [ -e $TAGENT_BASE/run/$runUser ]; then
                perl -i -pe s/tagent\.id=.*/tagent.id=/ $TAGENT_BASE/run/$runUser/conf/tagent.conf
        fi
}

linux7_install() {
        svcRoot='/usr/lib/systemd/system'
        if [ ! -e "$svcRoot" ] && [ -e '/lib/systemd/system' ]; then
                svcRoot='/lib/systemd/system'
        fi

        if [ "$runUser" = "root" ]; then
                cp $CWD/tagent.service $svcRoot/tagent.service
                perl -i -pe "s/TAGENT_BASE/$basePrefix/g" $svcRoot/tagent.service
                perl -i -pe "s/TAGENT_HOME/$homePrefix/g" $svcRoot/tagent.service
                perl -i -pe "s/SUDO//g" $svcRoot/tagent.service
                systemctl daemon-reload
                systemctl enable tagent.service
                systemctl start tagent.service

                echo "Service tagent installed."
        else
                cp $CWD/tagent.service $svcRoot/tagent-$runUser.service
                perl -i -pe "s/TAGENT_BASE/$basePrefix/g" $svcRoot/tagent-$runUser.service
                perl -i -pe "s/TAGENT_HOME/$homePrefix/g" $svcRoot/tagent-$runUser.service
                perl -i -pe "s/SUDO/$runUser/g" $svcRoot/tagent-$runUser.service
                systemctl daemon-reload
                systemctl enable tagent-$runUser.service
                systemctl start tagent-$runUser.service

                echo "Service tagent-$runUser installed."
        fi
}

linux_install() {
        if [ "$runUser" = "root" ]; then
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
                cp $CWD/tagent.init.d /etc/init.d/tagent-$runUser
                perl -i -pe "s/^\s*RUN_USER=/RUN_USER=$runUser/" /etc/init.d/tagent-$runUser
                perl -i -pe "s/^\s*TAGENT_BASE=/TAGENT_BASE=$basePrefix/" /etc/init.d/tagent-$runUser
                chmod 755 /etc/init.d/tagent-$runUser
                chkconfig --add tagent-$runUser
                chkconfig --level=3 tagent-$runUser on
                chkconfig --level=4 tagent-$runUser on
                chkconfig --level=5 tagent-$runUser on

                service tagent-$runUser start
                echo "Service tagent-$runUser installed."
        fi
}

aix_install() {
        if [ "$runUser" = "root" ]; then
                #add entry tagent to /etc/inittab
                mkitab "tagent:2:wait:$TAGENT_BASE/bin/tagent start $TAGENT_HOME > /dev/console 2>&1"
                $TAGENT_BASE/bin/tagent start $TAGENT_HOME
                echo "Service tagent installed."
        else
                #add entry tagent-$runUser to /etc/inittab
                mkitab "tagent-$runUser:2:wait:sudo -u $runUser $TAGENT_BASE/bin/tagent start $TAGENT_HOME > /dev/console 2>&1"
                sudo -u $runUser $TAGENT_BASE/bin/tagent start $TAGENT_HOME

                echo "Service tagent-$runUser installed."
        fi
}

sunos_install() {
        if [ "$runUser" = "root" ]; then
                #generate tagent.xml in /lib/svc/manifest/site/tagent.xml
                svcbundle -i -s service-name=application/tagent \
                        -s start-method="$TAGENT_BASE/bin/tagent start $TAGENT_HOME" \
                        -s stop-method="$TAGENT_BASE/bin/tagent stop $TAGENT_HOME"
                #start the service, must use option '-t', disable without option '-t' will disable the service permently
                svcadm enable -t application/tagent

                echo "Service tagent-root installed."
        else
                #generate tagent-$runUser.xml in /lib/svc/manifest/site/tagent-$runUser.xml
                svcbundle -i -s service-name=application/tagent-$runUser \
                        -s start-method="sudo -u $runUser $TAGENT_BASE/bin/tagent start $TAGENT_HOME" \
                        -s stop-method="sudo -u $runUser $TAGENT_BASE/bin/tagent stop $TAGENT_HOME"
                #start the service, must use option '-t', disable without option '-t' will disable the service permently
                svcadm enable -t application/tagent-$runUser

                echo "Service tagent-$runUser installed."
        fi
}

linux7_uninstall() {
        svcRoot='/usr/lib/systemd/system'
        if [ ! -e "$svcRoot" ] && [ -e '/lib/systemd/system' ]; then
                svcRoot='/lib/systemd/system'
        fi

        if [ "$runUser" = "root" ]; then
                systemctl stop tagent
                systemctl disable tagent.service
                rm $svcRoot/tagent.service
                systemctl daemon-reload
                echo "Service tagent uninstalled."
                systemctl list-unit-files | grep tagent
        else
                systemctl stop tagent-$runUser
                systemctl disable tagent-$runUser.service
                rm $svcRoot/tagent-$runUser.service
                systemctl daemon-reload
                echo "Service tagent uninstalled."
                systemctl list-unit-files | grep tagent-$runUser
        fi
}

linux_uninstall() {
        if [ "$runUser" = "root" ]; then
                service tagent stop
                chkconfig --del tagent
                rm /etc/init.d/tagent
                echo "Service tagent uninstalled."
                chkconfig --list | grep tagent
        else
                service tagent-$runUser stop
                chkconfig --del tagent-$runUser
                rm /etc/init.d/tagent-$runUser
                echo "Service tagent-$runUser uninstalled."
                chkconfig --list | grep tagent-$runUser
        fi
}

aix_uninstall() {
        if [ "$runUser" = "root" ]; then
                $TAGENT_BASE/bin/tagent stop $TAGENT_HOME
                #remove entry tagent in /etc/inittab
                rmitab "tagent"
                echo "Service tagent uninstalled."
        else
                sudo -u $runUser $TAGENT_BASE/bin/tagent stop $TAGENT_HOME
                #remove entry tagent-$runUser in /etc/inittab
                rmitab "tagent-$runUser"
                echo "Service tagent-$runUser uninstalled."
        fi
}

sunos_uninstall() {
        if [ "$runUser" = "root" ]; then
                #disable tagent service permently
                svcadm disable application/tagent
                rm /lib/svc/manifest/site/tagent.xml
                svcadm restart manifest-import
                echo "Service tagent uninstalled."
        else
                #disable tagent-$runUser service permently
                svcadm disable application/tagent-$runUser
                rm /lib/svc/manifest/site/tagent-$runUser.xml
                svcadm restart manifest-import
        fi
        echo "Service tagent-$runUser uninstalled."
}

kernel=$(uname -s 2>&1)

if [ "$action" = "uninstall" ]; then
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
