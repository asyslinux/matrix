#!/bin/bash

#Variables

CURIP=`dig +short txt ch whoami.cloudflare @1.1.1.1 | tr -d \"`

#Functions

valid_address()
{
    ip -4 route save match $1 > /dev/null 2>&1
}

if ! valid_address $CURIP; then

echo ""
echo "Error: invalid current external ip address: $CURIP"
echo ""

exit 1

fi

#Main

if [ -z "$CURIP" ]; then

echo ""
echo "Error: empty current external ip address: $CURIP"
echo ""

exit 1

fi

TRNIP=`cat /etc/turnserver.conf | grep "external-ip=$CURIP" | grep -v "#"`

if [ -z "$TRNIP" ]; then

TRNIP=`cat /etc/turnserver.conf | grep "external-ip=" | grep -v "#"`

sed -i -e "s/$TRNIP/external-ip=$CURIP/" /etc/turnserver.conf 2>/dev/null && systemctl restart coturn

fi

#END