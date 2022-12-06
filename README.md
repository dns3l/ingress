[![CI workflow](https://img.shields.io/github/workflow/status/dns3l/ingress/main?label=ci&logo=github)](https://github.com/dns3l/ingress/actions/workflows/main.yml)
[![GitHub release](https://img.shields.io/github/release/dns3l/ingress.svg&logo=github)](https://github.com/dns3l/ingress/releases/latest)
[![Semantic Release](https://img.shields.io/badge/semantic--release-angular-e10079?logo=semantic-release)](https://github.com/semantic-release/semantic-release)
![License](https://img.shields.io/github/license/dns3l/ingress)

## [NGINX][1] Ingress proxy for DNS3L

`docker pull ghcr.io/dns3l/ingress`

[1]: https://nginx.org/en/docs

### Configuration

| variable | note | default |
| --- | --- | --- |
| ENVIRONMENT | `production` or other deployments | |
| DNS3L_FQDN | published DNS3L FQDN | `localhost` |
| DNS3L_APP_URL | nuxt endpoint | `http://web:3000` |
| DNS3L_AUTH_URL | dex endpoint | `https://auth:5554/auth` |
| DNS3L_DAEMON_URL | dns3ld endpoint | `http://dns3ld:8880/api` |
| CERT_URL | bootstrap certificate for FQDN | `${DNS3L_DAEMON_URL}/ca/les/crt/${DNS3L_FQDN}` |
| CLIENT_ID | auth client ID | `dns3l-api` |
| CLIENT_SECRET | auth client secret | random |
| DNS3L_USER | user to feed the cert | `certbot` |
| DNS3L_PASS | user password | random |

If `CERT_URL` doesn't exist a selfsigned is created instead.

Mount a custom nginx config to `/etc/nginx.conf` if environment based template seems not sufficient.

### Multihomed

If you need to provide multiple URL for DNS3L stack, there is the issue that [Dex][2] always publishes a single issuer URL to the client.

In that case you can spawn multiple Dex instances that share the same config expect the issuer URL

```yaml
# dex instance 1
issuer: https://dns3l.example.com/auth

# dex instance 2
issuer: https://foo.example.com/auth

# dex instance 3
issuer: https://bar.example.com/auth
```

and set `DNS3L_FQDN` to `dns3l.example.com foo.example.com bar.example.com`. Space separated.
The first name is the certificate name by convention. Make sure the following names are included as SAN.

Or you mount a custom nginx config with the following tweaks.

```nginx
  map $host $auth {
    dns3l.example.com https://auth1:5554/auth;
    foo.example.com https://auth2:5554/auth;
    bar.example.com https://auth3:5554/auth;
    default https://auth:5554/auth;
  }
  server {
    server_name dns3l.example.com foo.example.com bar.example.com;
  }
```



[2]: https://dexidp.io/