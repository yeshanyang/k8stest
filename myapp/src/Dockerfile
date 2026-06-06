# ---- Build: copy static files with version info ----
FROM busybox:1.37 AS builder
WORKDIR /build

# Inject build-time variables via ARG
ARG APP_VERSION=dev
ARG BUILD_ID=local
ARG CANARY=false

COPY index.html /build/index.html

# Replace placeholders
RUN sed -i "s|APP_VERSION|${APP_VERSION}|g" index.html && \
    sed -i "s|BUILD_ID|${BUILD_ID}|g" index.html && \
    if [ "$CANARY" = "true" ]; then \
      sed -i "s|CANARY_CLASS|canary|g" index.html && \
      sed -i "s|CANARY_LABEL|CANARY|g" index.html; \
    else \
      sed -i "s|CANARY_CLASS|stable|g" index.html && \
      sed -i "s|CANARY_LABEL|STABLE|g" index.html; \
    fi

# ---- Runtime: serve via nginx ----
FROM nginx:1.27-alpine
COPY --from=builder /build/index.html /usr/share/nginx/html/index.html
COPY <<EOF /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    location / {
        try_files /index.html =200;
    }
    location /healthz {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
EOF
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s CMD wget -qO- http://localhost/healthz || exit 1
CMD ["nginx", "-g", "daemon off;"]
