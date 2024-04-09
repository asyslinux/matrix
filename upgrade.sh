#!/bin/bash

#Variables

HM=$(cd `dirname $0` && pwd)
SRC="/root/go/src"

DBNVERS=`test -f /etc/debian_version && cat /etc/debian_version | awk -F '.' '{print $1}' | bc`

if [ -z "$DBNVERS" ] || [ $DBNVERS -ne 11 ] && [ $DBNVERS -ne 12 ] && [ $DBNVERS -ne 13 ]; then

echo ""
echo "Error: linux distribution version is not supported"
echo "Only supported Debian 11/12/13 linux distributions"
echo ""
exit 1

fi

if [ $DBNVERS -eq 11 ]; then
PGVERS="13"
elif [ $DBNVERS -eq 12 ]; then
PGVERS="15"
elif [ $DBNVERS -eq 13 ]; then
PGVERS="17"
fi

source $HM/config.conf || exit 1

if [ -z "$DOMAIN" ]; then

echo ""
echo "Error: not configured domain in $HM/config.conf file"
echo ""

exit 1

fi

TASK="$1"

#Functions

errors() {

if [ ! -z "$1" ]; then

echo ""
echo "Error: $1"
echo ""

fi

exit 1

}

#Checks

if [ -z "$TASK" ] || [ "$TASK" != "upgrade" ]; then

echo ""
echo "Error: bad arguments"
echo ""
echo "Examples:"
echo ""
echo "bash $0 upgrade"
echo ""

exit 1

fi

#Main

cd $HM

test -f /etc/logrotate.d/dendrite && rm -f /etc/logrotate.d/dendrite # Remove non-needed external logrotate, dendrite have internal logrotate

if [ "$TASK" = "upgrade" ]; then

apt update || errors "Can not apt update"
apt upgrade || errors "Can not apt upgrade"

test -f $HM/go${GOVERS}.linux-amd64.tar.gz || wget -c https://go.dev/dl/go${GOVERS}.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go${GOVERS}.linux-amd64.tar.gz

export GO111MODULE=on
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

cd $SRC

test -d $SRC/dendrite && rm -rf $SRC/dendrite
git clone --single-branch --branch ${DNDRVERS} https://github.com/matrix-org/dendrite || errors "Can not update dendrite"
cd $SRC/dendrite && go build -o bin/ ./cmd/... || errors "Can not build dendrite"
rsync -av $SRC/dendrite/bin/* /usr/local/bin/ || errors "Can not copy dendrite binary files from $SRC/dendrite/bin/* to /usr/local/bin/"

rsync -av $HM/coturn-update-ssl.sh /usr/local/bin/ || errors "Can not copy $HM/coturn-update-ssl.sh update coturn ssl script to /usr/local/bin/"
rsync -av $HM/coturn-get-extip.sh /usr/local/bin/ || errors "Can not copy $HM/coturn-get-extip.sh update coturn ip script to /usr/local/bin/"
sed -i -e "s#DOMAIN#$DOMAIN#g" /usr/local/bin/coturn-update-ssl.sh || errors "Can not set domain in /usr/local/bin/coturn-update-ssl.sh"

systemctl start caddy && systemctl restart caddy || errors "Can not restart caddy service"
systemctl start coturn && systemctl restart coturn || errors "Can not restart coturn service"
systemctl start postgresql@$PGVERS-$PGNAME && systemctl restart postgresql@$PGVERS-$PGNAME || errors "Can not restart postgresql@$PGVERS-$PGNAME service"
systemctl start dendrite && systemctl restart dendrite || errors "Can not restart dendrite service"

#End Message

echo ""
echo "Successfully upgraded"
echo ""

else

echo ""
echo "Error: task $TASK is not supported"
echo ""

fi

#END