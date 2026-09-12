FROM alpine:latest

# Install ttyd, nginx, and curl (to fetch marked.js at build time)
RUN apk add --no-cache ttyd nginx curl \
    && mkdir -p /usr/share/nginx/html \
    && curl -fsSL https://cdn.jsdelivr.net/npm/marked/marked.min.js \
       -o /usr/share/nginx/html/marked.min.js

# Copy Nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy frontend assets
COPY frontend/index.html /usr/share/nginx/html/index.html

# Copy and make the startup script executable
COPY start.sh /start.sh
RUN chmod +x /start.sh

# ttyd (7681) is internal; only the Nginx frontend port is published
EXPOSE 8080

ENTRYPOINT ["/start.sh"]
