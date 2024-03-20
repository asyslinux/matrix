#!/bin/bash

/usr/bin/rsync -av /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/DOMAIN/* /usr/local/etc/ssl/DOMAIN/
chown -R turnserver:turnserver /usr/local/etc/ssl/DOMAIN
systemctl restart coturn

#END