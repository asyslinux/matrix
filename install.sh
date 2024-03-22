#!/bin/bash

#Variables

HM=$(cd `dirname $0` && pwd)
SRC="/root/go/src"
DBNVERS=`test -f /etc/debian_version && cat /etc/debian_version | awk -F '.' '{print $1}' | bc`

if [ -f /etc/dendrite/INITIALIZED.flag ]; then

echo ""
echo "Error: matrix is already initialized"
echo "Pleas DO NOT RUN again: bash $0 initial"
echo ""

exit 1

fi

if [ -z "$DBNVERS" ] || [ $DBNVERS -ne 11 ] && [ $DBNVERS -ne 12 ] && [ $DBNVERS -ne 13 ]; then

echo ""
echo "Error: linux distribution version is not supported"
echo "Only supported Debian 11/12/13 linux distributions"
echo ""

exit 1

fi

if [ ! -f $HM/config.conf ]; then

echo ""
echo "Error: $HM/config.conf file does not exists"
echo "Please first copy $HM/config-sample.conf to $HM/config.conf and edit options in configuration file:"
echo ""
echo "test -f $HM/config.conf || cp $HM/config-sample.conf $HM/config.conf"
echo "mcedit $HM/config.conf"
echo ""

exit 1

else

chmod 0600 $HM/config.conf || errors "Can not change mode on $HM/config.conf file"

fi

apt update && apt -y install pwgen dnsutils || exit 1

ADMINTMPLPWD=`pwgen -cns 32 -1`
TURNTMPLPWD=`pwgen -cns 32 -1`
SHAREDTMPLPWD=`pwgen -cns 32 -1`
PGTMPLPWD=`pwgen -cns 32 -1`

sed -i -e "s#ADMINTMPLPWD#$ADMINTMPLPWD#" $HM/config.conf
sed -i -e "s#TURNTMPLPWD#$TURNTMPLPWD#" $HM/config.conf
sed -i -e "s#SHAREDTMPLPWD#$SHAREDTMPLPWD#" $HM/config.conf
sed -i -e "s#PGTMPLPWD#$PGTMPLPWD#" $HM/config.conf

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

if [ -z "$TASK" ] || [ "$TASK" != "initial" ]; then

echo ""
echo "Error: bad arguments"
echo ""
echo "Examples:"
echo ""
echo "bash $0 initial"
echo ""

exit 1

fi

#Main

cd $HM

if [ "$TASK" = "initial" ]; then

apt -y install debian-keyring debian-archive-keyring apt-transport-https cron rsyslog mc screen psmisc pwgen dnsutils imvirt dialog locales wget curl systemd-timesyncd coturn rsync git build-essential postgresql bc || errors "Can not install initial apt packages"

systemctl enable rsyslog || errors "Can not enable rsyslog service"
systemctl start rsyslog && systemctl restart rsyslog || errors "Can not start rsyslog service"

if [ ! -f /usr/bin/caddy ]; then

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list

apt update && apt install caddy || errors "Can not install caddy web server"

fi

VM=$(imvirt)

if [ "$VM" != "OpenVZ" ] && [ "$VM" != "LXC" ]; then

apt -y remove --purge iptables || errors "Can not remove old iptables firewall"
apt -y install nftables || errors "Can not install new nftables firewall"

rsync -av $HM/nftables.conf /etc/ || errors "Can not copy $HM/nftables.conf configuration file to /etc/"

sed -i -e "s#TURNTLSPORT#$TURNTLSPORT#g" /etc/nftables.conf || errors "Can not set turn tls port in /etc/nftables.conf file"
sed -i -e "s#TURNALSPORT#$TURNALSPORT#g" /etc/nftables.conf || errors "Can not set turn alternative tls port in /etc/nftables.conf file"

systemctl enable nftables || errors "Can not enable nftables firewall service"
systemctl start nftables || errors "Can not start nftables firewall service"

rsync -av $HM/sysctl.conf /etc/ || errors "Can not copy $HM/sysctl.conf configuration file to /etc/"

sysctl -p || errors "Can not activate /etc/sysctl.conf kernel settings"

fi

systemctl enable systemd-timesyncd || errors "Can not enable systemd-timesyncd service"
systemctl start systemd-timesyncd || errors "Can not start systemd-timesyncd service"

rsync -av $HM/limits.conf /etc/security/ || errors "Can not copy $HM/limits.conf configuration file to /etc/security/"

dpkg-reconfigure locales # You need add en_US.UTF-8/ru_RU.UTF-8 locales and select by default en_US.UTF-8 locale

#Install Go Language

test -f $HM/go${GOVERS}.linux-amd64.tar.gz || wget -c https://go.dev/dl/go${GOVERS}.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go${GOVERS}.linux-amd64.tar.gz

export GO111MODULE=on
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

go version || errors "Can not find installed go language"

cat /etc/profile | grep GO111MODULE 1>/dev/null || echo 'export GO111MODULE=on' >> /etc/profile
cat /etc/profile | grep GOROOT 1>/dev/null || echo 'export GOROOT=/usr/local/go' >> /etc/profile
cat /etc/profile | grep GOPATH 1>/dev/null || echo 'export GOPATH=$HOME/go' >> /etc/profile
cat /etc/profile | grep 'GOPATH/bin' 1>/dev/null || echo 'export PATH=$GOPATH/bin:$GOROOT/bin:$PATH' >> /etc/profile

#Install Dendrite

mkdir -p $SRC && cd $SRC || errors "Can not create $SRC directory"
test -d $SRC/dendrite || git clone --single-branch --branch ${DNDRVERS} https://github.com/matrix-org/dendrite
cd $SRC/dendrite && go build -o bin/ ./cmd/... || errors "Can not build dendrite"

rsync -av $SRC/dendrite/bin/* /usr/local/bin/ || errors "Can not copy dendrite binary files from $SRC/dendrite/bin/* to /usr/local/bin/"

test -d /etc/dendrite || mkdir /etc/dendrite

test -d /var/lib/dendrite/storage || mkdir -p /var/lib/dendrite/storage
test -d /var/lib/dendrite/media-storage || mkdir -p /var/lib/dendrite/media-storage
test -d /var/lib/dendrite/search-index || mkdir -p /var/lib/dendrite/search-index
test -d /var/lib/dendrite/databases || mkdir -p /var/lib/dendrite/databases

test -d /var/log/dendrite || mkdir /var/log/dendrite

groupadd -f dendrite
id -u dendrite &>/dev/null || useradd dendrite -g dendrite -s /usr/sbin/nologin

if [ ! -f /etc/dendrite/dendrite_key_$DOMAIN.pem ]; then

if [ ! -f $HM/dendrite_key_$DOMAIN.pem ]; then

generate-keys --private-key $HM/dendrite_key_$DOMAIN.pem && rsync -av $HM/dendrite_key_$DOMAIN.pem /etc/dendrite/ || errors "Can not generate and copy $HM/dendrite_key_$DOMAIN.pem federation dendrite key to /etc/dendrite/"

else

rsync -av $HM/dendrite_key_$DOMAIN.pem /etc/dendrite/ || errors "Can not copy $HM/dendrite_key_$DOMAIN.pem federation dendrite key to /etc/dendrite/"

fi

fi

rsync -av $HM/dendrite.yaml /etc/dendrite || errors "Can not copy $HM/dendrite.yaml configuration file to /etc/dendrite/"
rsync -av $HM/turnserver.conf /etc/ || errors "Can not copy $HM/turnserver.conf configuration file to /etc/"
rsync -av $HM/dendrite /etc/logrotate.d/ || errors "Can not copy $HM/dendrite configuration file to /etc/logrotate.d/"

sed -i -e "s#DOMAIN#$DOMAIN#g" /etc/dendrite/dendrite.yaml || errors "Can not set domain in /etc/dendrite/dendrite.yaml file"
sed -i -e "s#TURNTLSPORT#$TURNTLSPORT#" /etc/dendrite/dendrite.yaml || errors "Can not set turn tls port in /etc/dendrite/dendrite.yaml file"
sed -i -e "s#TURNUSERNAME#$TURNUSERNAME#" /etc/dendrite/dendrite.yaml || errors "Can not set turn username in /etc/dendrite/dendrite.yaml file"
sed -i -e "s#TURNPASSWORD#$TURNPASSWORD#g" /etc/dendrite/dendrite.yaml || errors "Can not set turn username in /etc/dendrite/dendrite.yaml file"
sed -i -e "s#SSHARED#$SSHARED#" /etc/dendrite/dendrite.yaml || errors "Can not set shared secret in /etc/dendrite/dendrite.yaml file"

sed -i -e "s#PGUSERNAME#$PGUSERNAME#" /etc/dendrite/dendrite.yaml || errors "Can not set postgresql username in /etc/dendrite/dendrite.yaml file"
sed -i -e "s#PGPASSWORD#$PGPASSWORD#" /etc/dendrite/dendrite.yaml || errors "Can not set postgresql password in /etc/dendrite/dendrite.yaml file"
sed -i -e "s#PGDATABASE#$PGDATABASE#" /etc/dendrite/dendrite.yaml || errors "Can not set postgresql database in /etc/dendrite/dendrite.yaml file"

sed -i -e "s#DOMAIN#$DOMAIN#g" /etc/turnserver.conf || errors "Can not set domain in /etc/turnserver.conf file"
sed -i -e "s#TURNUSERNAME#$TURNUSERNAME#" /etc/turnserver.conf || errors "Can not set turn username in /etc/turnserver.conf file"
sed -i -e "s#TURNPASSWORD#$TURNPASSWORD#g" /etc/turnserver.conf || errors "Can not set turn password/auth-secret in /etc/turnserver.conf file"
sed -i -e "s#TURNLISTENIP#$TURNLISTENIP#" /etc/turnserver.conf || errors "Can not set turn listen ip in /etc/turnserver.conf file"
sed -i -e "s#TURNRELAYIP#$TURNRELAYIP#" /etc/turnserver.conf || errors "Can not set turn relay ip in /etc/turnserver.conf file"

if [ ! -z "$TURNEXTERNALIP" ]; then

sed -i -e "s#\#external-ip=TURNEXTERNALIP#external-ip=$TURNEXTERNALIP#" /etc/turnserver.conf || errors "Can not set turn external ip in /etc/turnserver.conf file"

fi

sed -i -e "s#TURNTLSPORT#$TURNTLSPORT#" /etc/turnserver.conf || errors "Can not set turn tls port in /etc/turnserver.conf file"
sed -i -e "s#TURNALSPORT#$TURNALSPORT#" /etc/turnserver.conf || errors "Can not set turn alternative tls port in /etc/turnserver.conf file"

chown -R dendrite:dendrite /etc/dendrite || errors "Can not recursive change owner and group on /etc/dendrite directory"
chown -R dendrite:dendrite /var/lib/dendrite || errors "Can not recursive change owner and group on /var/lib/dendrite directory"
chown -R dendrite:dendrite /var/log/dendrite || errors "Can not recursive change owner and group on /var/log/dendrite directory"
chmod 0700 /etc/dendrite || errors "Can not change mode on /etc/dendrite directory"
chmod -R 0700 /var/lib/dendrite || errors "Can not change mode on /var/lib/dendrite directory"
chmod 0600 /etc/dendrite/* || errors "Can not change mode on /etc/dendrite/* files"

chown root:turnserver /etc/turnserver.conf || errors "Can not change owner and group on /etc/turnserver.conf file"
chmod 0640 /etc/turnserver.conf || errors "Can not change mode on /etc/turnserver.conf file"

rsync -av $HM/Caddyfile /etc/caddy/ || errors "Can not copy $HM/Caddyfile configuration file to /etc/caddy/"
sed -i -e "s#DOMAIN#$DOMAIN#g" /etc/caddy/Caddyfile || errors "Can not set domain in /etc/caddy/Caddyfile file"

systemctl enable caddy || errors "Can not enable caddy service"
systemctl start caddy && systemctl restart caddy || errors "Can not start caddy service"

if [ ! -d /usr/local/etc/ssl/$DOMAIN ]; then

sleep 15
rsync -av /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN /usr/local/etc/ssl/ || errors "Can not copy SSL certificate and key to /usr/local/etc/"
chown -R turnserver:turnserver /usr/local/etc/ssl/$DOMAIN || errors "Can not recursive change owner and group on /usr/local/etc/ssl/$DOMAIN"

fi

systemctl enable coturn || errors "Can not enable coturn service"
systemctl start coturn && sleep 3 && systemctl restart coturn || errors "Can not start coturn service"

if [ $DBNVERS -eq 11 ]; then
PGVERS="13"
elif [ $DBNVERS -eq 12 ]; then
PGVERS="15"
elif [ $DBNVERS -eq 13 ]; then
PGVERS="17"
fi

if [ -d /etc/postgresql/$PGVERS/main ]; then

systemctl stop postgresql@$PGVERS-main
pg_dropcluster --stop $PGVERS main
systemctl disable postgresql || errors "Can not disable postgresql.service default systemd script"
systemctl disable postgresql@$PGVERS-main || errors "Can not disable postgresql@$PGVERS-main default systemd script"

fi

sleep 5

if [ ! -d /etc/postgresql/$PGVERS/dendrite ]; then

pg_createcluster --start --start-conf=auto --locale ru_RU.UTF-8 --lc-collate ru_RU.UTF-8 -p $PGPORT $PGVERS $PGNAME -- --auth trust --auth-local trust --auth-host trust || exit 1

echo "host    all             all             0.0.0.0/0                md5" >> /etc/postgresql/$PGVERS/$PGNAME/pg_hba.conf || exit 1

pg_conftool $PGVERS $PGNAME set huge_pages try || errors "Can not setup postgresql configuration option"

pg_conftool $PGVERS $PGNAME set listen_addresses '"127.0.0.1"' || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set port $PGPORT || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_connections 256 || errors "Can not setup postgresql configuration option"

pg_conftool $PGVERS $PGNAME set max_worker_processes 128 || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_parallel_workers_per_gather 2 || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_parallel_workers 2 || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set autovacuum_max_workers 2 || errors "Can not setup postgresql configuration option"

pg_conftool $PGVERS $PGNAME set shared_buffers 128MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set temp_buffers 2MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set work_mem 1MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set maintenance_work_mem 64MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set effective_cache_size 64MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_files_per_process 1024 || errors "Can not setup postgresql configuration option"

pg_conftool $PGVERS $PGNAME set synchronous_commit local || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set wal_level replica || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_wal_senders 8 || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_replication_slots 4 || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set wal_compression on || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set wal_buffers 16MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_wal_size 4GB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set min_wal_size 128MB || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set wal_keep_size 16384 || errors "Can not setup postgresql configuration option"

pg_conftool $PGVERS $PGNAME set max_standby_archive_delay 14400s || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set max_standby_streaming_delay 14400s || errors "Can not setup postgresql configuration option"

pg_conftool $PGVERS $PGNAME set deadlock_timeout 60s || errors "Can not setup postgresql configuration option"
pg_conftool $PGVERS $PGNAME set log_lock_waits on || errors "Can not setup postgresql configuration option"

systemctl enable postgresql@$PGVERS-$PGNAME || errors "Can not enable postgresql@$PGVERS-$PGNAME systemd script"
systemctl restart postgresql@$PGVERS-$PGNAME || errors "Can not restart postgresql@$PGVERS-$PGNAME service"

sleep 5

psql -U postgres -h 127.0.0.1 -p $PGPORT -c "CREATE DATABASE $PGDATABASE;" || errors "Cannot create postgresql database: $PGDATABASE"

psql -U postgres -h 127.0.0.1 -p $PGPORT -c "CREATE USER $PGUSERNAME;" || errors "Cannot create postgresql username: $PGUSERNAME"
psql -U postgres -h 127.0.0.1 -p $PGPORT -c "ALTER USER $PGUSERNAME WITH ENCRYPTED PASSWORD '$PGPASSWORD';" || errors "Cannot create postgresql password: $PGPASSWORD for user: $PGUSERNAME"
psql -U postgres -h 127.0.0.1 -p $PGPORT -c "GRANT ALL PRIVILEGES ON DATABASE $PGDATABASE TO $PGUSERNAME;" || errors "Cannot create postgresql privileges for database: $PGDATABASE on user: $PGUSERNAME"

psql -U postgres -h 127.0.0.1 -p $PGPORT -d $PGDATABASE -c "GRANT ALL ON SCHEMA public TO public;" || errors "Cannot grant privileges public to public in database: $PGDATABASE"
psql -U postgres -h 127.0.0.1 -p $PGPORT -d $PGDATABASE -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $PGUSERNAME;" || errors "Cannot create postgresql privileges for database: $PGDATABASE on user: $PGUSERNAME"
psql -U postgres -h 127.0.0.1 -p $PGPORT -d $PGDATABASE -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $PGUSERNAME;" || errors "Cannot create postgresql privileges for database: $PGDATABASE on user: $PGUSERNAME"

fi

crontab -l -u root | cat - $HM/cron.conf | crontab -u root - || errors "Can not add task to cron from $HM/cron.conf configuration file"
rsync -av $HM/coturn-update-ssl.sh /usr/local/bin/ || errors "Can not copy $HM/coturn-update-ssl.sh update coturn ssl script to /usr/local/bin/"
rsync -av $HM/coturn-get-extip.sh /usr/local/bin/ || errors "Can not copy $HM/coturn-get-extip.sh update coturn ip script to /usr/local/bin/"

sed -i -e "s#DOMAIN#$DOMAIN#g" /usr/local/bin/coturn-update-ssl.sh || errors "Can not set domain in /usr/local/bin/coturn-update-ssl.sh"

rsync -av $HM/dcreate /usr/local/bin/ || errors "Can not copy $HM/dcreate admin script to /usr/local/bin/"
rsync -av $HM/dpasswd /usr/local/bin/ || errors "Can not copy $HM/dcreate admin script to /usr/local/bin/"
rsync -av $HM/daccmod /usr/local/bin/ || errors "Can not copy $HM/daccmod admin script to /usr/local/bin/"

chmod 0700 /usr/local/bin/dcreate || errors "Can not change mode on /usr/local/bin/dcreate file"
chmod 0700 /usr/local/bin/dpasswd || errors "Can not change mode on /usr/local/bin/dpasswd file"
chmod 0700 /usr/local/bin/daccmod || errors "Can not change mode on /usr/local/bin/daccmod file"

rsync -av $HM/dendrite.service /lib/systemd/system/ || errors "Can not copy $HM/dendrite.service unit file to /lib/systemd/system/"
sed -i -e "s#PGVERS#$PGVERS#g" /lib/systemd/system/dendrite.service || errors "Can not set postgresql version in /lib/systemd/system/"

systemctl daemon-reload || errors "Can not reload systemd daemon"
systemctl enable dendrite || errors "Can not enable dendrite service"
systemctl start dendrite && systemctl restart dendrite || errors "Can not start dendrite service"

sleep 15

#Create Administrator User

if [ ! -f /etc/dendrite/INITIALIZED.flag ]; then

ADMINTOKEN=`/usr/local/bin/dcreate admin "$ADMINPASSWORD" --admin &> /dev/stdout | awk -F 'AccessToken:' '{print $2}' | sed -e 's/^[ \t]*//' | awk -F ')"' '{print $1}'`

sed -i -e "s#DOMAIN#$DOMAIN#" /usr/local/bin/dpasswd || errors "Can not set domain in /usr/local/bin/dpasswd"
sed -i -e "s#ADMINTOKEN#$ADMINTOKEN#" /usr/local/bin/dpasswd || errors "Can not set administrator token in /usr/local/bin/daccmod"

sed -i -e "s#DOMAIN#$DOMAIN#" /usr/local/bin/daccmod || errors "Can not set domain in /usr/local/bin/daccmod"
sed -i -e "s#ADMINTOKEN#$ADMINTOKEN#" /usr/local/bin/daccmod || errors "Can not set administrator token in /usr/local/bin/daccmod"

fi

#Information About Server Settings

echo "Matrix server: $DOMAIN"
echo "Main administrator account: admin / @admin:$DOMAIN"
echo "Main administrator password: $ADMINPASSWORD"
echo "Main administrator token: $ADMINTOKEN"
echo ""
echo "All scripts:"
echo ""
echo "/usr/local/bin/dcreate - create dendrite matrix accounts like @account:$DOMAIN"
echo "/usr/local/bin/dpasswd - change password for dendrite matrix accounts"
echo "/usr/local/bin/daccmod - deacivate matrix dendrite accounts and other tools"
echo ""

echo "How to create matrix accounts:"

test -x /usr/local/bin/dcreate && /usr/local/bin/dcreate help

echo "How to change password on matrix accounts:"

test -x /usr/local/bin/dpasswd && /usr/local/bin/dpasswd help

echo "How to enable or disable matrix accounts:"

test -x /usr/local/bin/daccmod && /usr/local/bin/daccmod help

#Restart Cron

systemctl restart cron

touch /etc/dendrite/INITIALIZED.flag

#End Message

echo "Successfully initialized"
echo ""

else

echo ""
echo "Error: task $TASK is not supported"
echo ""

fi

#END