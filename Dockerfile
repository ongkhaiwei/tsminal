FROM ubuntu:24.04

USER root

ENV DEBIAN_FRONTEND=noninteractive
# Use bash as the default shell for all RUN instructions
SHELL ["/bin/bash", "-i", "-l", "-c"]
# Ensure bash is used as the login shell for the container user
ENV ENV=/root/.bashrc

# In rootless build environments (e.g. OpenShift), apt cannot chown/chmod its
# cache dirs. Fix: disable the sandbox user and take ownership of the dirs upfront.
RUN echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/00sandbox \
    && chown -R root:root /var/cache/apt /var/lib/apt \
    && chmod -R 755 /var/cache/apt /var/lib/apt \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        nginx \
        ttyd \
        curl \
    && rm -rf /var/cache/apt/archives/*.deb /var/lib/apt/lists/*

# ── Frontend assets ───────────────────────────────────────────────────────────
RUN curl -fsSL https://cdn.jsdelivr.net/npm/marked/marked.min.js \
       -o /usr/share/nginx/html/marked.min.js

# ── Nginx log/lib dirs: fix ownership for OpenShift arbitrary-UID runtime ─────
RUN chown -R root:root /var/log/nginx /var/lib/nginx \
    && chmod -R 777 /var/log/nginx /var/lib/nginx

# ── Bash configuration ────────────────────────────────────────────────────────
# Write a .bashrc that enables full interactive features:
#   - bash-completion for Tab-completion of commands, flags, and paths
#   - persistent command history across sessions
#   - a colour prompt showing user@host:cwd
RUN apt-get update && apt-get install -y --no-install-recommends bash-completion \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'source /etc/bash_completion' >> /root/.bashrc \
    && echo 'export HISTFILE=/root/.bash_history' >> /root/.bashrc \
    && echo 'export HISTSIZE=1000' >> /root/.bashrc \
    && echo 'export HISTFILESIZE=2000' >> /root/.bashrc \
    && echo 'export PS1="\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ "' >> /root/.bashrc

COPY nginx.conf /etc/nginx/nginx.conf
COPY frontend/index.html /usr/share/nginx/html/index.html
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8080

ENTRYPOINT ["/start.sh"]
