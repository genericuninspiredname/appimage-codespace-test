FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Preinstall the lightweight WebKit-based browser (GNOME Web) into the
# cached image so codespace creation is fast. desktop-lite provides the
# desktop, D-Bus, fonts, file manager, editor, and terminal.
COPY install-apps.sh /tmp/install-apps.sh
RUN bash /tmp/install-apps.sh && rm -f /tmp/install-apps.sh
