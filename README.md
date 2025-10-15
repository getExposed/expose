# Expose
Reverse HTTP/TCP proxy tunnel via secure SSH connections.

# Automated
## Installers

### Server
Systemd setup: For Linux servers, run the installer with `WITH_SYSTEMD=1 and (optionally) EXPOSE_DOMAIN, EXPOSE_HTTPADDR, EXPOSE_SSHADDR, EXPOSE_PASSWORD` set:

```bash
WITH_SYSTEMD=1 EXPOSE_DOMAIN=example.com EXPOSE_HTTPADDR=0.0.0.0:80 EXPOSE_SSHADDR=0.0.0.0:2200 \
/bin/bash -c "$(curl -fsSL https://dl.getexposed.io/server.sh)"
```

### Client
```bash
/bin/bash -c "$(curl -fsSL https://dl.getexposed.io/agent.sh)"

```
# From Source
## Client
### Installation
You can download prebuild binaries [here](https://github.com/getExposed/expose/releases).

### Build from source
First, clone the repository
```bash
git clone https://github.com/getExposed/expose.git
```
Then install client:

```bash
make install_dependencies
make
cp ./build/expose /usr/local/bin/expose
```
This will compile and install expose client locally.

### Establish tunnel on hosted example.com

Let's say you are running HTTP server locally on port 6500, then command would be:

```bash
expose -s example.com -p 2200 -ls localhost -lp 6500
```

2200 is port where expose-server is running and localhost:6500 is local HTTP server.

Example output:

```bash
expose -s example.com -p 2200 -ls localhost -lp 6500

Generated HTTP URL: http://918574de.example.com
Generated HTTPS URL: https://918574de.example.com
Direct TCP: tcp://example.com:60637
```

Then open generated URL in the browser to check if it works, then share the URL if needed.

You can also request custom id instead of randomly generated one:
```bash
expose -lp 6500 -id myapp

Generated HTTP URL: http://myapp.example.com
Generated HTTPS URL: https://myapp.example.com
Direct TCP: tcp://example.com:55474
```

If custom requested ID is already taken, then random id is used.

You can also specify custom remote bind listening port, which is useful for using direct TCP connection:
```bash
expose -lp 6500 -bp 55000

Generated HTTP URL: http://fe2d57f3.example.com
Generated HTTPS URL: https://fe2d57f3.example.com
Direct TCP: tcp://example.com:55000
```

Note that for hosted expose you need to specify port in range 45000-65000.

If port is already taken, random port is used.

## Running Server
### Run Compilation
```bash
make install_dependencies
make
```

### Running expose-server example
```
EXPOSE_DOMAIN=example.com EXPOSE_HTTPADDR=0.0.0.0:80 EXPOSE_SSHADDR=0.0.0.0:2200 ./build/expose-server
```
This will generate initial config at ~/expose/expose-server.yaml with values you provided over environment variables.

### Running With Password Authentication
To enable password authentication, you can set it up with the EXPOSE_PASSWORD environment variable:

### Server Side
EXPOSE_DOMAIN=example.com EXPOSE_HTTPADDR=0.0.0.0:80 EXPOSE_SSHADDR=0.0.0.0:2200 EXPOSE_PASSWORD=mysecreetpassword ./build/expose-server

### Client Side
Use the -pw flag to provide the password when connecting to the server:

```
expose -s example.com -p 2200 -ls localhost -lp 6500 -pw mysecreetpassword
```
If the password is incorrect or not provided when required, the connection will be rejected with an authentication error.

### Reverse proxy with nginx
```
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
	listen 80 default_server;
	listen [::]:80 default_server;

	root /var/www/html;

	index index.html index.htm index.nginx-debian.html;

        server_name ~^(?<subdomain>[a-z0-9]+)\.example\.com$;

    return 301 https://$host$request_uri;
}

server {
	listen 443 ssl;
	server_name ~^(?<subdomain>[a-z0-9]+)\.example\.com$;

	ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

	location / {
        	proxy_pass http://127.0.0.1:2000;
    		proxy_http_version 1.1;
	        proxy_set_header Connection $connection_upgrade;
	    	proxy_set_header Upgrade $http_upgrade;
	        proxy_set_header Host $host;
        	proxy_set_header X-Real-IP $remote_addr;
	        proxy_set_header X-Forwarded-For  $proxy_add_x_forwarded_for;
        	proxy_set_header X-Forwarded-Proto $scheme;
    		proxy_read_timeout 3600s;
	        proxy_send_timeout 3600s;
		    proxy_request_buffering off;
	        proxy_buffering off;
	}
}
```

### Running as a service
Create a expose user, and its directories
```bash
sudo mkdir -p /etc/expose /var/lib/expose /var/log/expose
sudo useradd --system --home /var/lib/expose --shell /usr/sbin/nologin expose
sudo chown -R expose:expose /etc/expose /var/lib/expose /var/log/expose

```

Create a service definition
```
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
# Light hardening (optional; uncomment once paths are correct)
# ProtectSystem=strict
# ProtectHome=yes
# PrivateTmp=yes
# NoNewPrivileges=yes
# ReadWritePaths=/var/lib/expose /var/log/expose /etc/expose
# AmbientCapabilities=
# CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
```

if you want to password protect your deployment - include the password value,

You can generate a secure password with `openssl rand -base64 32`

```
openssl rand -base64 32
MqBsp+oA/RI2T2vnLSQoAUCqsYwUWv1axoAtNHOLulM=
```

ensure the expose config file exists in `/etc/expose/expose-server.yaml`
```yaml
domain: getexposed.io
httpaddr: 0.0.0.0:2000
log:
    filename: /var/log/expose/expose-server.log
    level: debug
    max_age: 3
    max_backups: 3
    max_size: 500
    stdout: true
privatekey: /etc/expose/id_rsa
publickey: /etc/expose/id_rsa.pub
sshaddr: 0.0.0.0:2200
password: "MqBsp+oA/RI2T2vnLSQoAUCqsYwUWv1axoAtNHOLulM="
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now expose-server
```

You can watch the logs, either with `journalctl -u expose-server -f`
or `tail -f /var/log/expose/expose-server.log`

