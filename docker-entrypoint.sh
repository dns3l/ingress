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

# return true if specified directory is empty
function directory_empty() {
  [ -n "$(find "${1}"/ -prune -empty)" ]
}

function random_token() {
  tr -cd '[:alnum:]' </dev/urandom | fold -w32 | head -n1
}

# inspired by https://www.rfc-editor.org/rfc/rfc3986#appendix-B
# //URL prefix required. Not for IPv6 ([2001:db8::7]) addresses.
readonly URI_REGEX='^(([^:/?#]+):)?(//((([^:/?#]+)@)?([^:/?#]+)(:([0-9]+))?))?(/([^?#]*))?(\?([^#]*))?(#(.*))?'
protFromURL () {
    [[ "$@" =~ $URI_REGEX ]] && echo "${BASH_REMATCH[2],,}"
}
hostFromURL () {
    [[ "$@" =~ $URI_REGEX ]] && echo "${BASH_REMATCH[7],,}"
}
portFromURL () {
    if [[ "$@" =~ $URI_REGEX ]]; then
      if [[ -z "${BASH_REMATCH[9]}" ]]; then
        case "${BASH_REMATCH[2],,}" in
          # some default ports...
          http)  echo "80" ;;
          https) echo "443" ;;
          ldap)  echo "389" ;;
          ldaps) echo "636" ;;
        esac
      else
        echo "${BASH_REMATCH[9]}"
      fi
    fi
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
export DNS3L_APP_TIMEOUT=${DNS3L_APP_TIMEOUT:-1m}
export DNS3L_API_TIMEOUT=${DNS3L_API_TIMEOUT:-6m}
export DNS3L_AUTH_TIMEOUT=${DNS3L_AUTH_TIMEOUT:-2m}

: "${DNS3L_TOKEN:?not set or empty}"

# Review dead lock behavior once authn is enabled in dns3ld
#   https://github.com/dns3l/ingress/issues/3
#   https://github.com/dns3l/dns3l-core/issues/19
export DNS3L_BOOT_DAEMON_URL=${DNS3L_BOOT_DAEMON_URL:-"http://dns3ld:8880/api"}

if [ -r /etc/nginx.conf -a -s /etc/nginx.conf ]; then
  ln -fs /etc/nginx.conf /etc/nginx/nginx.conf
else
  /dckrz -template /etc/nginx/nginx.tmpl:/etc/nginx/nginx.conf

  # Template usage is waiting for deps...
  # Review dead lock behavior once authn is enabled in dns3ld
  #   https://github.com/dns3l/ingress/issues/3
  #   https://github.com/dns3l/dns3l-core/issues/19
  /dckrz -wait ${DNS3L_BOOT_DAEMON_URL}/info -skip-tls-verify -timeout ${SERVICE_TIMEOUT} -- echo "Ok. DNS3L bootstrap daemon is there."
fi

###
### Bootstrap TLS...
###

DNS3L_FQDN_CA=${DNS3L_FQDN_CA:-les}
read -a fqdns <<< $DNS3L_FQDN
CERT_NAME=${fqdns[0]} # first FQDN is the cert name
CERT_URL=${DNS3L_BOOT_DAEMON_URL}/ca/${DNS3L_FQDN_CA}/crt/${CERT_NAME}

found=1

set +e
curl -k -s -H "X-DNS3L-Access-Token: ${DNS3L_TOKEN}" ${CERT_URL}/pem/key |\
  tee /etc/nginx/privkey.pem | grep -q -- '-----BEGIN .* PRIVATE KEY-----'
if [[ $? != "0" ]]; then
  echo Oooops. Key ${CERT_URL}/pem/key not found.
  found=0
fi
curl -k -s -H "X-DNS3L-Access-Token: ${DNS3L_TOKEN}" ${CERT_URL}/pem/fullchain |\
  tee /etc/nginx/fullchain.pem | grep -q -- '-----BEGIN CERTIFICATE-----'
if [[ $? != "0" ]]; then
  echo Oooops. Cert ${CERT_URL}/pem/fullchain not found.
  found=0
fi
set -e
sync

if [[ $found == "0" ]]; then
  echo Generate selfsigned cert/key pair
  openssl req -x509 -batch -newkey rsa:4096 -sha256 -days 90 -nodes \
              -keyout /etc/nginx/privkey.pem -out /etc/nginx/fullchain.pem \
              -subj "/CN=${CERT_NAME}" \
              -addext "keyUsage=critical,digitalSignature,keyAgreement" \
              -addext "extendedKeyUsage=serverAuth" \
              -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
else
  echo Key ${CERT_URL}/pem/key applied.
  echo Cert ${CERT_URL}/pem/fullchain applied.
fi

###
### Start cron...
###

crond -lnotice -L/proc/1/fd/1

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
