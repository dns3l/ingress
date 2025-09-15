#!/bin/bash

function random_token() {
  tr -cd '[:alnum:]' </dev/urandom | fold -w32 | head -n1
}

DNS3L_FQDN=${DNS3L_FQDN:-localhost}
read -a fqdns <<< $DNS3L_FQDN
CERT_NAME=${fqdns[0]} # first FQDN is the cert name
DNS3L_FQDN_CA=${DNS3L_FQDN_CA:-les}
DNS3L_DAEMON_URL=${DNS3L_DAEMON_URL:-"http://dns3ld:8880/api"}
CERT_URL=${DNS3L_DAEMON_URL}/ca/${DNS3L_FQDN_CA}/crt/${CERT_NAME}

: "${DNS3L_TOKEN:?not set or empty}"

SRV_HOST=${SRV_HOST:-ingress}
SRV_PORT=${SRV_PORT:-443}

# grab SSL TTL from our running service
SRV_TTL=`echo | openssl s_client -servername ${SRV_HOST} -connect ${SRV_HOST}:${SRV_PORT} 2>/dev/null |\
  openssl x509 -noout -dates 2>/dev/null | grep ^notAfter | cut -d= -f2`

LOG=/proc/1/fd/1
echo "[$(date)] Cert selfcare: Check for (re)new(ed) cert..." >$LOG

# grab SSL TTL from DNS3L for our service
DNS3L_TTL=`curl -k -s -H "X-DNS3L-API-Key: ${DNS3L_TOKEN}" ${CERT_URL}/pem/crt |\
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
  curl -k -s -H "X-DNS3L-API-Key: ${DNS3L_TOKEN}" ${CERT_URL}/pem/key > /etc/nginx/privkey.pem
  curl -k -s -H "X-DNS3L-API-Key: ${DNS3L_TOKEN}" ${CERT_URL}/pem/fullchain > /etc/nginx/fullchain.pem

  # restart/reload our service...
  kill -s SIGHUP 1
  exit 1
else
  echo "Cert selfcare: Nothing to do..." >$LOG
  echo "Cert selfcare: DNS3L TTL: $DNS3L_TTL" >$LOG
  echo "Cert selfcare: Service TTL: $SRV_TTL" >$LOG
  exit 0
fi
