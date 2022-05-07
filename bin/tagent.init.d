#!/bin/bash
### BEGIN INIT INFO
# Provides: techsure
# USAGE: tagent start|stop|status
# chkconfig: 3 99 01
# description: techsure automation agent
# Short-Description: ts tagent
# Required-Start:    $local_fs
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# start:   Starts the service
# stop:    Stops the service
# status:  monitor the service
### END INIT INFO


# Source function library.
#. /etc/rc.d/init.d/functions

# Source networking configuration.
#. /etc/sysconfig/network

RUN_USER=
TAGENT_BASE=
TAGENT_HOME=$TAGENT_BASE/run/$RUN_USER
export TAGENT_BASE
export TAGENT_HOME

start(){
    ulimit -n 131072
    if [ "$RUN_USER" = "root" ]
    then 
        $TAGENT_BASE/bin/tagent start $TAGENT_HOME
    else
        sudo -u $RUN_USER $TAGENT_BASE/bin/tagent start $TAGENT_HOME
    fi
}

stop(){
    if [ "$RUN_USER" = "root" ]
    then
        $TAGENT_BASE/bin/tagent stop $TAGENT_HOME
    else
        sudo -u $RUN_USER $TAGENT_BASE/bin/tagent stop $TAGENT_HOME
    fi
}

restart(){
    stop
    start
}

status(){
    if [ "$RUN_USER" = "root" ]
    then
        $TAGENT_BASE/bin/tagent status $TAGENT_HOME
    else
        sudo -u $RUN_USER $TAGENT_BASE/bin/tagent status $TAGENT_HOME
    fi
}

# See how we were called.
case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  status)
    status
    ;;
  restart)
    restart
    ;;
  *)
    echo $"Usage: $0 {start|stop|status|restart}"
    exit 2
esac

exit $?

