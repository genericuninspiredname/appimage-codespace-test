FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Core applications (Firefox, system GL stack, htop, age for backups) are
# preinstalled into the cached image so codespace creation is fast. Optional
# applications (PrismLauncher) are opt-in via the OPTIONAL_APPS build arg -
# a space-separated list of tokens (prism). Changing it requires a container
# rebuild; see README.
# desktop-lite provides the desktop, D-Bus, fonts, file manager, editor,
# and terminal.
ARG OPTIONAL_APPS=""
COPY install-apps.sh /tmp/install-apps.sh
RUN OPTIONAL_APPS="$OPTIONAL_APPS" bash /tmp/install-apps.sh && rm -f /tmp/install-apps.sh
