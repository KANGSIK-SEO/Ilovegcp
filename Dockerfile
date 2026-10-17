FROM nginx:1.27-alpine

LABEL maintainer="KANGSIK-SEO"
LABEL description="Ilovegcp Cloud Mission Web Service (Nginx + /health endpoint)"

RUN apk add --no-cache curl

COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY web/index.html /usr/share/nginx/html/index.html
COPY web/health /usr/share/nginx/html/health

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=2s --retries=3 \
  CMD curl -fsS http://localhost/health || exit 1
