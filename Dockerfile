FROM nginx:1.23-alpine

LABEL org.opencontainers.image.title="dns3l NGINX ingress"
LABEL org.opencontainers.image.description="A docker compose ingress for DNS3L"
LABEL org.opencontainers.image.version=1.0.2

ENV VERSION=1.0.2

ENV PAGER=less

ARG http_proxy
ARG https_proxy
ARG no_proxy

# provided via BuildKit
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# defaults for none BuildKit
ENV _platform=${TARGETPLATFORM:-linux/amd64}
ENV _os=${TARGETOS:-linux}
ENV _arch=${TARGETARCH:-amd64}
ENV _variant=${TARGETVARIANT:-}

# coreutils setup timeout and fixing a bug in wait-for-it.sh
# with BusyBox timeout
RUN apk --update upgrade && \
    apk add --no-cache coreutils \
        ca-certificates curl less bash busybox-extras \
        sudo jq wget dcron openssl bind-tools joe

# Install dockerize
#
ENV DCKRZ_VERSION="0.16.3"
RUN _arch=${_arch/amd64/x86_64} && curl -fsSL https://github.com/powerman/dockerize/releases/download/v$DCKRZ_VERSION/dockerize-${_os}-${_arch}${_variant} > /dckrz && \
    chmod a+x /dckrz

RUN curl -fsSL https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/nginx/dhparam

COPY nginx.conf /etc/nginx/nginx.tmpl
COPY nginx.renew.sh /etc/periodic/daily/nginx-renew
COPY docker-entrypoint.sh /entrypoint.sh

EXPOSE 80 443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
