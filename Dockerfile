FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Audio support + CJK fonts (needed by the browser desktop)
RUN apt-get update -qq \
 && apt-get install -y -qq pulseaudio pavucontrol fonts-noto-cjk >/dev/null \
 && apt-get clean

# Preinstall apps into the image so codespace creation is fast
COPY install-apps.sh /tmp/install-apps.sh
RUN bash /tmp/install-apps.sh && rm -f /tmp/install-apps.sh
