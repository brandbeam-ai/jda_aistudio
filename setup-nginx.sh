#!/bin/bash

# Nginx reverse proxy + SSL for JD Alchemy AI Studio (Next.js via PM2)
# Run ON THE Vultr server (same layout as deploy.sh: /root/jda_aistudio, PORT 3025)
# Usage: sudo bash setup-nginx.sh
#   Or from the repo: cd /root/jda_aistudio && sudo bash ./setup-nginx.sh

set -e

# Configuration (override with env vars if needed)
DOMAIN="${DOMAIN:-aistudio.jdalchemy.com}"
APP_PORT="${APP_PORT:-3025}"
EMAIL="${EMAIL:-jay@jdalchemy.com}"
# Include www in certificate + server_name (set false if DNS for www is not set)
INCLUDE_WWW="${INCLUDE_WWW:-true}"

# App directory: same as deploy.sh clone target; auto-detect if this script lives in the repo
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
if [[ -f "${SCRIPT_DIR}/package.json" ]] && grep -q '"next"' "${SCRIPT_DIR}/package.json" 2>/dev/null; then
  APP_DIR="${APP_DIR:-$SCRIPT_DIR}"
else
  APP_DIR="${APP_DIR:-/root/jda_aistudio}"
fi

# Rate limit zone names (must be unique; defined in conf.d snippet)
RL_ZONE_REQ="jda_aistudio_req"
RL_ZONE_CONN="jda_aistudio_conn"
NGINX_RATE_LIMIT_CONF="/etc/nginx/conf.d/00-jda-aistudio-rate-limit.conf"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔧 Setting up Nginx for ${DOMAIN}...${NC}"
echo -e "${YELLOW}   Backend: 127.0.0.1:${APP_PORT} (Next.js / PM2)${NC}"
echo -e "${YELLOW}   App dir: ${APP_DIR}${NC}"

# server_name and certbot domains (optional www)
if [[ "${INCLUDE_WWW}" == "true" ]] || [[ "${INCLUDE_WWW}" == "1" ]]; then
  SERVER_NAMES="${DOMAIN} www.${DOMAIN}"
  CERTBOT_DOMAINS=(-d "${DOMAIN}" -d "www.${DOMAIN}")
else
  SERVER_NAMES="${DOMAIN}"
  CERTBOT_DOMAINS=(-d "${DOMAIN}")
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Please run as root (use sudo)${NC}"
  exit 1
fi

# Check if Nginx is installed
if ! command -v nginx &> /dev/null; then
  echo -e "${YELLOW}📥 Installing Nginx...${NC}"
  apt update
  apt install -y nginx
fi

# Check if Certbot is installed
if ! command -v certbot &> /dev/null; then
  echo -e "${YELLOW}📥 Installing Certbot...${NC}"
  apt install -y certbot python3-certbot-nginx
fi

echo -e "${YELLOW}📝 Step 0: http-context snippets (rate limits + WebSocket map)...${NC}"
# These must live in http { } — conf.d/*.conf is included on Ubuntu/Debian
cat > "${NGINX_RATE_LIMIT_CONF}" << EOF
# Managed by setup-nginx.sh — zones referenced by ${DOMAIN} site
limit_req_zone \$binary_remote_addr zone=${RL_ZONE_REQ}:10m rate=10r/s;
limit_conn_zone \$binary_remote_addr zone=${RL_ZONE_CONN}:10m;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
EOF
echo -e "${GREEN}✅ Wrote ${NGINX_RATE_LIMIT_CONF}${NC}"

echo -e "${YELLOW}📝 Step 1: Creating initial Nginx configuration (HTTP only)...${NC}"

# Backup existing config if it exists
if [ -f /etc/nginx/sites-available/${DOMAIN} ]; then
  cp /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-available/${DOMAIN}.backup.$(date +%Y%m%d_%H%M%S)
  echo -e "${GREEN}✅ Backed up existing configuration${NC}"
fi

# Create initial HTTP-only configuration for Certbot verification
# Note: Certbot will modify this to add HTTPS and redirects
cat > /etc/nginx/sites-available/${DOMAIN} << EOF

# HTTP — Certbot will add SSL server blocks and redirect to HTTPS
# Next.js (next start) behind PM2: 127.0.0.1:${APP_PORT}
upstream nextjs_${APP_PORT} {
    server 127.0.0.1:${APP_PORT};
}

server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAMES};

    server_tokens off;
    merge_slashes on;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;

    client_max_body_size 50M;

    # Do not send HSTS on plain HTTP — add HSTS on the HTTPS server block after SSL (or via Next.js headers)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    gzip on;
    gzip_vary on;
    gzip_types text/css text/javascript application/javascript application/json image/svg+xml;
    gzip_proxied expired no-cache no-store private auth;

    location ~* \.(env|git|svn|htaccess|htpasswd|ini|log|sh|sql|bak|backup|swp|conf)$ {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location / {
        limit_req zone=${RL_ZONE_REQ} burst=20 nodelay;
        limit_conn ${RL_ZONE_CONN} 20;

        proxy_pass http://nextjs_${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_cache_bypass \$http_upgrade;

        proxy_buffering off;
        proxy_request_buffering off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /_next/static {
        proxy_pass http://nextjs_${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        expires 365d;
        add_header Cache-Control "public, immutable";
    }

    location /_next/image {
        proxy_pass http://nextjs_${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|mp4|webp)$ {
        proxy_pass http://nextjs_${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    location /health {
        access_log off;
        limit_req zone=${RL_ZONE_REQ} burst=5 nodelay;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

echo -e "${GREEN}✅ Nginx configuration created${NC}"

echo -e "${YELLOW}🔗 Step 2: Enabling site...${NC}"

# Create symbolic link to enable the site
ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}

# Remove default site if exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
    echo -e "${GREEN}✅ Removed default site${NC}"
fi

# Ensure no conflicting configurations are active
echo -e "${YELLOW}🧹 Cleaning up any conflicting configurations...${NC}"
# Remove any other default SSL configs that might interfere
rm -f /etc/nginx/sites-enabled/default-ssl 2>/dev/null || true

echo -e "${YELLOW}🧪 Step 3: Testing Nginx configuration...${NC}"

nginx -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Nginx configuration is valid${NC}"
else
    echo -e "${RED}❌ Nginx configuration has errors${NC}"
    exit 1
fi

echo -e "${YELLOW}🔄 Step 4: Reloading Nginx...${NC}"

systemctl reload nginx

echo -e "${GREEN}✅ Nginx reloaded${NC}"

echo -e "${YELLOW}🔐 Step 5: Setting up SSL certificate with Certbot...${NC}"
echo "This may take a few moments..."

# Obtain SSL certificate (apex + optional www, see INCLUDE_WWW)
certbot --nginx "${CERTBOT_DOMAINS[@]}" --non-interactive --agree-tos --email "${EMAIL}" --redirect

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SSL certificate obtained and configured${NC}"
else
    echo -e "${YELLOW}⚠️  SSL certificate setup failed or skipped${NC}"
    echo "This might be because:"
    echo "  1. DNS records are not pointing to this server yet"
    echo "  2. Port 80 and 443 are not open in firewall"
    echo "  3. Domain is not accessible from internet"
    echo ""
    echo "You can set up SSL later by running:"
    echo "  certbot --nginx ${CERTBOT_DOMAINS[*]}"
    echo ""
    echo -e "${GREEN}✅ HTTP configuration is ready. Test at: http://${DOMAIN}${NC}"
fi

echo -e "${YELLOW}🔄 Step 6: Final Nginx reload...${NC}"

systemctl reload nginx

echo -e "${YELLOW}🔍 Step 6.5: Verifying HTTPS redirects for www and non-www...${NC}"

# Check if SSL was successfully configured
if certbot certificates | grep -q "${DOMAIN}"; then
    # Verify the configuration has proper redirects for both www and non-www
    HTTP_REDIRECT_COUNT=$(grep -c "return 301 https" /etc/nginx/sites-available/${DOMAIN} || echo "0")
    
    if [ "$HTTP_REDIRECT_COUNT" -ge "1" ]; then
        echo -e "${GREEN}✅ HTTPS redirects are configured${NC}"
        
        # Check if both www and non-www have redirects
        if [[ "${INCLUDE_WWW}" == "true" ]] || [[ "${INCLUDE_WWW}" == "1" ]]; then
          if grep -q "server_name ${DOMAIN}" /etc/nginx/sites-available/${DOMAIN} && grep -q "www.${DOMAIN}" /etc/nginx/sites-available/${DOMAIN}; then
            echo -e "${GREEN}✅ Apex and www appear in nginx config${NC}"
          fi
        else
          echo -e "${GREEN}✅ HTTPS enabled (INCLUDE_WWW=false, apex only)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  HTTPS redirects may not be properly configured. Certbot should have added them.${NC}"
        echo -e "${YELLOW}   You may need to manually verify the configuration.${NC}"
    fi
    
    # Test the configuration
    echo -e "${YELLOW}🧪 Testing Nginx configuration after SSL setup...${NC}"
    nginx -t
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Nginx configuration is valid${NC}"
    else
        echo -e "${RED}❌ Nginx configuration has errors - please check manually${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  SSL not configured yet, skipping redirect verification${NC}"
    if [[ "${INCLUDE_WWW}" == "true" ]] || [[ "${INCLUDE_WWW}" == "1" ]]; then
      echo -e "${YELLOW}   Once SSL is set up, http://${DOMAIN} and http://www.${DOMAIN} should redirect to HTTPS${NC}"
    else
      echo -e "${YELLOW}   Once SSL is set up, http://${DOMAIN} should redirect to HTTPS${NC}"
    fi
fi

echo -e "${YELLOW}⚙️  Step 7: Setting up auto-renewal for SSL certificate...${NC}"

# Test auto-renewal (only if certificate was obtained)
if certbot certificates | grep -q "${DOMAIN}"; then
    certbot renew --dry-run
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ SSL auto-renewal is configured${NC}"
    else
        echo -e "${YELLOW}⚠️  SSL auto-renewal test had issues (but certificate is installed)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  SSL certificate not found, skipping auto-renewal test${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📊 Configuration Summary:"
echo "  Domain: ${DOMAIN}"
echo "  INCLUDE_WWW: ${INCLUDE_WWW}"
echo "  Backend: 127.0.0.1:${APP_PORT} (Next.js via PM2 — see deploy.sh)"
echo "  App Directory: ${APP_DIR}"
if certbot certificates | grep -q "${DOMAIN}"; then
    echo "  SSL: Enabled ✅"
else
    echo "  SSL: Not configured (HTTP only for now)"
fi
echo ""
echo "🌐 Your site is now available at:"
if certbot certificates | grep -q "${DOMAIN}"; then
    echo "  https://${DOMAIN}"
    if [[ "${INCLUDE_WWW}" == "true" ]] || [[ "${INCLUDE_WWW}" == "1" ]]; then
      echo "  https://www.${DOMAIN}"
      echo ""
      echo "  http://${DOMAIN} and http://www.${DOMAIN} redirect to HTTPS"
    else
      echo ""
      echo "  http://${DOMAIN} redirects to HTTPS"
    fi
else
    echo "  http://${DOMAIN}"
    if [[ "${INCLUDE_WWW}" == "true" ]] || [[ "${INCLUDE_WWW}" == "1" ]]; then
      echo "  http://www.${DOMAIN}"
    fi
    echo ""
    echo "  Note: Run certbot when DNS is ready to enable HTTPS"
fi
echo ""
echo "📋 Useful commands:"
echo "  systemctl status nginx    - Check Nginx status"
echo "  systemctl reload nginx    - Reload Nginx configuration"
echo "  certbot renew             - Manually renew SSL certificate"
echo "  certbot certificates      - List all certificates"
echo "  tail -f /var/log/nginx/${DOMAIN}.access.log - View access logs"
echo "  tail -f /var/log/nginx/${DOMAIN}.error.log  - View error logs"
echo ""
if certbot certificates | grep -q "${DOMAIN}"; then
    echo "🔐 SSL Certificate will auto-renew before expiration"
else
    echo "🔐 To set up SSL later, run:"
    echo "   certbot --nginx ${CERTBOT_DOMAINS[*]}"
fi
echo ""

