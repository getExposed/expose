#!/usr/bin/env bash
set -euo pipefail

REPO="getExposed/expose"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CMD_NAME="expose-server"

# Optional quick config envs (used only if you enable systemd below)
EXPOSE_DOMAIN="${EXPOSE_DOMAIN:-example.com}"
EXPOSE_HTTPADDR="${EXPOSE_HTTPADDR:-0.0.0.0:80}"
EXPOSE_SSHADDR="${EXPOSE_SSHADDR:-0.0.0.0:2200}"
EXPOSE_PASSWORD="${EXPOSE_PASSWORD:-}"

WITH_SYSTEMD="${WITH_SYSTEMD:-0}"   # set to 1 to create a systemd service on Linux

# Detect OS
uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$uname_s" in
  linux)   os="linux" ;;
  darwin)  os="darwin" ;;
  freebsd) os="freebsd" ;;
  *) echo "Unsupported OS: $uname_s"; exit 1 ;;
esac

# Detect ARCH
uname_m="$(uname -m)"
case "$uname_m" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  armv7l|armv7|armv6l|armv6) arch="arm" ;;
  *) echo "Unsupported architecture: $uname_m"; exit 1 ;;
esac

asset="expose-server_${os}_${arch}"
url="https://github.com/${REPO}/releases/latest/download/${asset}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ${asset}..."
curl -fsSL -o "${tmp}/${CMD_NAME}" "$url"

chmod +x "${tmp}/${CMD_NAME}"
sudo install -m 0755 "${tmp}/${CMD_NAME}" "${INSTALL_DIR}/${CMD_NAME}"

echo "Installed ${CMD_NAME} to ${INSTALL_DIR}/${CMD_NAME}"

# Optional: create minimal config + systemd unit on Linux
if [ "$WITH_SYSTEMD" = "1" ] && [ "$os" = "linux" ]; then
  echo "Configuring systemd service..."
  sudo mkdir -p /etc/expose /var/lib/expose /var/log/expose
  if ! id expose >/dev/null 2>&1; then
    sudo useradd --system --home /var/lib/expose --shell /usr/sbin/nologin expose
  fi
  sudo chown -R expose:expose /etc/expose /var/lib/expose /var/log/expose

  cat <<YAML | sudo tee /etc/expose/expose-server.yaml >/dev/null
domain: ${EXPOSE_DOMAIN}
httpaddr: ${EXPOSE_HTTPADDR}
sshaddr: ${EXPOSE_SSHADDR}
log:
  filename: /var/log/expose/expose-server.log
  level: info
  max_age: 3
  max_backups: 3
  max_size: 200
  stdout: true
privatekey: /etc/expose/id_rsa
publickey: /etc/expose/id_rsa.pub
$( [ -n "$EXPOSE_PASSWORD" ] && echo "password: \"${$EXPOSE_PASSWORD}\"" )
YAML
  sudo ssh-keygen -t rsa -b 4096 -N "" -f /etc/expose/id_rsa >/dev/null 2>&1 || true
  sudo chown expose:expose /etc/expose/id_rsa /etc/expose/id_rsa.pub

  cat <<'UNIT' | sudo tee /etc/systemd/system/expose-server.service >/dev/null
[Unit]
Description=Expose Tunnel Relay Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=expose
Group=expose
WorkingDirectory=/var/lib/expose
ExecStart=/usr/local/bin/expose-server -config /etc/expose/expose-server.yaml
Restart=always
RestartSec=2
LimitNOFILE=65536
Environment=GOTRACEBACK=all
StandardOutput=journal
StandardError=journal
SyslogIdentifier=expose-server

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  sudo systemctl enable --now expose-server
  echo "expose-server systemd unit installed and started."
fi

"${INSTALL_DIR}/${CMD_NAME}" -h || true
