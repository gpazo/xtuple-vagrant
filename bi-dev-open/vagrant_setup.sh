#!/bin/sh
set -x

SERVICE=xtupleBi

# Set up the init.d script.  It's too late for it to run in this boot so we'll call it in the provisioner
cat <<xtupleBiEOF | sudo tee /etc/init.d/$SERVICE
#! /bin/bash
### BEGIN INIT INFO
# Provides:          xTuple-BI-Open
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Controls the open source version of xTuple BI
# Description:       Start/Stop xTuple BI service
### END INIT INFO

# Author: Jeff Gunderson <jgunderson@xtuple.com>
# Author: Gil Moskowitz  <gmoskowitz@xtuple.com>

# TODO: start with a fresh copy of /etc/init.d/skeleton and use
#       fewer custom scripts and more pentaho scripts

# Do NOT "set -e"

# PATH should only include /usr/* if it runs after the mountnfs.sh script
PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="xTuple Open BI"
PIDFILE=/var/run/${SERVICE}.pid
SCRIPTNAME=/etc/init.d/$SERVICE

# Exit if the package is not installed
[ -f /home/vagrant/dev/bi-open/scripts/start_bi.sh ] || exit 0

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.2-14) to ensure that this file is present
# and status_of_proc is working.
. /lib/lsb/init-functions

do_start()
{
  cd /home/vagrant/dev/bi-open/scripts
  bash start_bi.sh >> /var/log/$SERVICE 2>&1
  if [ \$? -ne 0 ] ; then
    return 2
  fi
  cd /home/vagrant/dev/xtuple/node-datasource
  sudo -u vagrant bash -c "node main.js | sudo tee -a /var/log/$SERVICE &"
  sleep 10
  ps auwwx | awk '/node main.js/ { print \$2}' | sudo tee \$PIDFILE
  return 0
}

do_stop()
{
  local RETVAL=1
  if [ -e \$PIDFILE ] ; then
    kill -9 \`cat \$PIDFILE\` >> /var/log/$SERVICE 2>&1
    rm -f \$PIDFILE
    cd /home/vagrant/dev/bi-open/scripts
    bash stop_bi.sh >> /var/log/$SERVICE 2>&1
    if [ \$? -ne 0 ] ; then
      RETVAL=2
    else
      RETVAL=0
    fi
  fi
  return $RETVAL
}

do_reload() {
  do_stop
  do_start
}

case "\$1" in
  start)
        [ "\$VERBOSE" != no ] && log_daemon_msg "Starting \$DESC" "\$NAME"
        do_start
        case "\$?" in
          0|1) [ "\$VERBOSE" != no ] && log_end_msg 0 ;;
            2) [ "\$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  stop)
        [ "\$VERBOSE" != no ] && log_daemon_msg "Stopping \$DESC" "\$NAME"
        do_stop
        case "\$?" in
                0|1) [ "\$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "\$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  restart|force-reload)
        log_daemon_msg "Restarting \$DESC" "\$NAME"
        do_stop
        case "\$?" in
          0|1)
                do_start
                case "\$?" in
                        0) log_end_msg 0 ;;
                        1) log_end_msg 1 ;; # Old process is still running
                        *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
          *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
  *)
        echo "Usage: \$SCRIPTNAME {start|stop|restart|force-reload}" >&2
        exit 3
        ;;
esac

exit 0
xtupleBiEOF

sudo update-rc.d $SERVICE defaults 98
sudo chmod +x /etc/init.d/$SERVICE

# Bootstrap
wget git.io/hikK5g -qO- | sudo bash

# TODO: Have trouble with git ssh authorization after xtuple-server install-dev is run (why?)
cd /home/vagrant/dev
echo FIXME: use XTUPLE for all repos! ==========================================
for REPO in xtuple/xtuple jgunderson/xtuple-extensions xtuple/bi-open ; do
  REPODIR=`basename $REPO`
  if [ ! -d "$REPODIR" ] ; then
    git clone https://github.com/${REPO}.git
    cd $REPODIR
    git submodule update --init --recursive
    cd ..
  fi
done

# Install xtuple-server
npm install -g xtuple-server

# Install xtuple-extensions
sudo chmod -R 777 /usr/local/lib
sudo n 0.10
cd xtuple-extensions
git checkout radar
git submodule update --init --recursive --quiet
npm install --quiet
cd ..

# Install xtuple
cd xtuple
npm install --quiet
cd ..

# Use the server to do an install and build xtuple (must be in the xtuple folder?)
sudo n 0.11
IPADDR=`ifconfig | awk '/192/ { split($2, addr, ":"); print addr[2] ; exit }'`
cd /home/vagrant
sudo xtuple-server install-dev --xt-demo --xt-adminpw admin --nginx-sslcnames $IPADDR --local-workspace /home/vagrant/dev/xtuple  --verbose

# Install BI and perform ETL
cd /home/vagrant/dev
sudo chmod -R 777 /usr/local/lib
cd bi-open/scripts
sudo -H bash build_bi.sh -eblm -c ../../xtuple/node-datasource/config.js -d demo_dev -P admin -n $IPADDR
cd ../..

# Install bi-open.
cd xtuple
sudo ./scripts/build_app.js -d demo_dev -e ../xtuple-extensions/source/bi_open
cd ..

sudo service $SERVICE start

echo "The xTuple Server install script is done!"
