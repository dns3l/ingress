FROM nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284

LABEL org.opencontainers.image.title="dns3l NGINX ingress"
LABEL org.opencontainers.image.description="A docker compose ingress for DNS3L"
LABEL org.opencontainers.image.version=1.1.1

ENV VERSION=1.1.1

# provided via BuildKit
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# defaults for none BuildKit
ARG _platform=${TARGETPLATFORM:-linux/amd64}
ARG _os=${TARGETOS:-linux}
ARG _arch=${TARGETARCH:-amd64}
ARG _variant=${TARGETVARIANT:-}

# coreutils setup timeout and fixing a bug in wait-for-it.sh with BusyBox timeout
RUN apk --update upgrade && \
    apk add --no-cache tini bash coreutils tzdata openssl ca-certificates curl busybox-extras dcron

# Install dockerize
# https://github.com/powerman/dockerize doesn't enabled SHA digests for assets via GitHub API
#
ARG DCKRZ_LINUX_AMD64_SHA256=9239915df1cc59b4ad3927f9aad6a36ffc256d459cff9b073ae9d7f9c9149a03
ARG DCKRZ_LINUX_ARM64_SHA256=3a11c2f207151c304e8cf7aef060cf30ce8d56979b346329087f3a2c6b6055cb
ENV DCKRZ_VERSION="0.24.0"
RUN curl -fsSL https://github.com/powerman/dockerize/releases/download/v${DCKRZ_VERSION}/dockerize-v${DCKRZ_VERSION}-${_os}-${_arch}${_variant} > /dckrz && \
    chmod a+x /dckrz && \
    echo "${DCKRZ_LINUX_AMD64_SHA256} */dckrz" >> /dckrz.sha256 && \
    echo "${DCKRZ_LINUX_ARM64_SHA256} */dckrz" >> /dckrz.sha256 && \
    sha256sum -c /dckrz.sha256 2>/dev/null | grep 'OK$'

RUN curl -fsSL https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/nginx/dhparam

COPY nginx.conf /etc/nginx/nginx.tmpl
COPY nginx.renew.sh /etc/periodic/daily/nginx-renew
COPY docker-entrypoint.sh /entrypoint.sh

EXPOSE 80 443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
