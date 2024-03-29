#!/bin/bash

function random_token() {
  tr -cd '[:alnum:]' </dev/urandom | fold -w32 | head -n1
}

DNS3L_FQDN=${DNS3L_FQDN:-localhost}
read -a fqdns <<< $DNS3L_FQDN
CERT_NAME=${fqdns[0]} # first FQDN is the cert name
DNS3L_FQDN_CA=${DNS3L_FQDN_CA:-les}
DNS3L_AUTH_URL=${DNS3L_BOOT_AUTH_URL:-"https://auth:5554/auth"}
DNS3L_DAEMON_URL=${DNS3L_DAEMON_URL:-"http://dns3ld:8880/api"}
CERT_URL=${DNS3L_DAEMON_URL}/ca/${DNS3L_FQDN_CA}/crt/${CERT_NAME}

SRV_HOST=${SRV_HOST:-ingress}
SRV_PORT=${SRV_PORT:-443}

# grab SSL TTL from our running service
SRV_TTL=`echo | openssl s_client -servername ${SRV_HOST} -connect ${SRV_HOST}:${SRV_PORT} 2>/dev/null |\
  openssl x509 -noout -dates 2>/dev/null | grep ^notAfter | cut -d= -f2`

CLIENT_ID=${CLIENT_ID:-"dns3l-api"}
CLIENT_SECRET=${CLIENT_SECRET:-$(random_token)}
DNS3L_USER=${DNS3L_USER:-certbot}
DNS3L_PASS=${DNS3L_PASS:-$(random_token)}

LOG=/proc/1/fd/1
echo "[$(date)] Cert selfcare: Check for (re)new(ed) cert..." >$LOG

ID_TOKEN=`curl -k -s -X POST -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&scope=openid profile email groups offline_access&username=${DNS3L_USER}&password=${DNS3L_PASS}" \
  ${DNS3L_AUTH_URL}/token | jq -r .id_token`
if [[ -z ${ID_TOKEN} || ${ID_TOKEN} == "null" ]]; then
  echo "Cert selfcare: Oooops. Invalid token." >$LOG
  exit 3
fi

# grab SSL TTL from DNS3L for our service
DNS3L_TTL=`curl -k -s -H "Authorization: Bearer ${ID_TOKEN}" ${CERT_URL}/pem/crt |\
  openssl x509 -noout -dates 2>/dev/null | grep ^notAfter | cut -d= -f2`

# compare...
if [ -z "$DNS3L_TTL" -o -z "$SRV_TTL" ]; then
  echo "Cert selfcare: Error fetching certs from ${SRV_HOST}:${SRV_PORT} or ${CERT_URL}" >$LOG
  exit 2
elif [ "$DNS3L_TTL" != "$SRV_TTL" ]; then
  # TODO: use real integer comparison (>) instead of equal strings...
  echo "Cert selfcare: Installing (re)new(ed) cert..." >$LOG
  echo "Cert selfcare: DNS3L TTL: $DNS3L_TTL" >$LOG
  echo "Cert selfcare: Service TTL: $SRV_TTL" >$LOG

  # install the renewed cert into our service
  # REVIEW: dangerous... in case of curl failure.
  curl -k -s -H "Authorization: Bearer ${ID_TOKEN}" ${CERT_URL}/pem/key > /etc/nginx/privkey.pem
  curl -k -s -H "Authorization: Bearer ${ID_TOKEN}" ${CERT_URL}/pem/fullchain > /etc/nginx/fullchain.pem

  # restart/reload our service...
  kill -s SIGHUP 1
  exit 1
else
  echo "Cert selfcare: Nothing to do..." >$LOG
  echo "Cert selfcare: DNS3L TTL: $DNS3L_TTL" >$LOG
  echo "Cert selfcare: Service TTL: $SRV_TTL" >$LOG
  exit 0
fi
