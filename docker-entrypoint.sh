#!/bin/bash
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
#  (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#   "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
function file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

# envs=(
#   XYZ_API_TOKEN
# )
# haveConfig=
# for e in "${envs[@]}"; do
#   file_env "$e"
#   if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
#     haveConfig=1
#   fi
# done

# return true if specified directory is empty
function directory_empty() {
  [ -n "$(find "${1}"/ -prune -empty)" ]
}

function random_token() {
  tr -cd '[:alnum:]' </dev/urandom | fold -w32 | head -n1
}

SERVICE_TIMEOUT=${SERVICE_TIMEOUT:-300s} # wait for dependencies

echo Running: "$@"

# Avoid destroying bootstrapping by simple start/stop
if [[ ! -e /.bootstrapped ]]; then
  ### list none idempotent code blocks, here...

  touch /.bootstrapped
fi

export DNS3L_FQDN=${DNS3L_FQDN:-localhost}
export DNS3L_APP_URL=${DNS3L_APP_URL:-"http://web:3000"}
export DNS3L_AUTH_URL=${DNS3L_AUTH_URL:-"https://auth:5554/auth"}
export DNS3L_DAEMON_URL=${DNS3L_DAEMON_URL:-"http://dns3ld:8880/api"}

if [ -r /etc/nginx.conf -a -s /etc/nginx.conf ]; then
  ln -fs /etc/nginx.conf /etc/nginx/nginx.conf
else
  /dckrz -template /etc/nginx/nginx.tmpl:/etc/nginx/nginx.conf

  # Template usage is waiting for deps...
  /dckrz -wait ${DNS3L_DAEMON_URL}/info -skip-tls-verify -timeout ${SERVICE_TIMEOUT} -- echo "Ok. DNS3L daemon is there."
  /dckrz -wait ${DNS3L_AUTH_URL}/.well-known/openid-configuration -skip-tls-verify -timeout ${SERVICE_TIMEOUT} -- echo "Ok. DexIDP is there."
fi

###
### Bootstrap TLS...
###

CERT_URL=${DNS3L_DAEMON_URL}/ca/les/crt/${DNS3L_FQDN}
CLIENT_ID=${CLIENT_ID:-"dns3l-api"}
CLIENT_SECRET=${CLIENT_SECRET:-$(random_token)}
DNS3L_USER=${DNS3L_USER:-certbot}
DNS3L_PASS=${DNS3L_PASS:-$(random_token)}

found=1

ID_TOKEN=`curl -k -s -X POST -u "${CLIENT_ID}:${CLIENT_SECRET}" \
  -d "grant_type=password&scope=openid profile email groups offline_access&username=${DNS3L_USER}&password=${DNS3L_PASS}" \
  ${DNS3L_AUTH_URL}/token | jq -r .id_token`

if [[ -z ${ID_TOKEN} || ${ID_TOKEN} == "null" ]]; then
  echo Oooops. Invalid token.
  found=0
fi

set +e
curl -k -s -H "Authorization: Bearer ${ID_TOKEN}" ${CERT_URL}/pem/key |\
  tee /etc/nginx/privkey.pem | grep -q -- '-----BEGIN .* PRIVATE KEY-----'
if [[ $? != "0" ]]; then
  echo Oooops. Key ${CERT_URL}/pem/key not found.
  found=0
fi
curl -k -s -H "Authorization: Bearer ${ID_TOKEN}" ${CERT_URL}/pem/fullchain |\
  tee /etc/nginx/fullchain.pem | grep -q -- '-----BEGIN CERTIFICATE-----'
if [[ $? != "0" ]]; then
  echo Oooops. Cert ${CERT_URL}/pem/fullchain not found.
  found=0
fi
set -e

if [[ $found == "0" ]]; then
  echo Generate selfsigned cert/key pair
  openssl req -x509 -batch -newkey rsa:4096 -sha256 -days 90 -nodes \
              -keyout /etc/nginx/privkey.pem -out /etc/nginx/fullchain.pem \
              -subj "/CN=${DNS3L_FQDN}" \
              -addext "basicConstraints=CA:false" \
              -addext "keyUsage=critical,digitalSignature,keyAgreement" \
              -addext "extendedKeyUsage=serverAuth" \
              -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
fi

###
### Start cron...
###

crond -L/dev/null
 
###
### Start nginx...
###

if [[ `basename ${1}` == "nginx" ]]; then # prod
  exec "$@" </dev/null #>/dev/null 2>&1
else # dev
  nginx
fi

# fallthrough...
exec "$@"
