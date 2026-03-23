#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting deployment of JD Alchemy AI Studio...${NC}"

# Clone the repository
echo -e "${GREEN}Cloning the repository...${NC}"
cd /root

if [ -d "jda_aistudio" ]; then
    echo -e "${YELLOW}Repository already exists. Pulling latest changes...${NC}"
    cd jda_aistudio
    git pull
else
    echo -e "${GREEN}Cloning fresh repository...${NC}"
    git clone <YOUR_REPOSITORY_URL> jda_aistudio
    cd jda_aistudio
fi

# Install dependencies
echo -e "${GREEN}Installing npm dependencies...${NC}"
npm install

# Build the application
echo -e "${GREEN}Building the application...${NC}"
# Set Node.js memory limit and disable interactive prompts
export NODE_OPTIONS="--max-old-space-size=2048"
export NODE_ENV=production
npm run build

# Setup PM2 configuration
echo -e "${GREEN}Setting up PM2 configuration...${NC}"
cat > ecosystem.config.js << EOL
module.exports = {
  apps: [{
    name: 'jda_aistudio',
    script: 'node_modules/next/dist/bin/next',
    args: 'start -p 3025 -H 127.0.0.1',
    instances: 1,
    exec_mode: 'fork',
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    }
  }]
};
EOL

# Start or restart the application with PM2
echo -e "${GREEN}Starting the application with PM2...${NC}"
# Stop and delete existing process first (if it exists)
pm2 stop jda_aistudio 2>/dev/null || true
pm2 delete jda_aistudio 2>/dev/null || true

# Kill any process still using the app port (must match nginx upstream + PORT above)
lsof -ti :3025 | xargs kill -9 2>/dev/null || true

# Wait a moment for port to be released
sleep 2

# Start the application
pm2 start ecosystem.config.js

# Save the current PM2 state (after starting, not before)
pm2 save

# Setup PM2 startup script (only needs to be run once, but safe to run multiple times)
pm2 startup 2>/dev/null || true

# Configure firewall if ufw is available (HTTP/HTTPS only; Next.js binds to 127.0.0.1 — use nginx)
if command -v ufw &> /dev/null; then
    echo -e "${GREEN}Configuring firewall...${NC}"
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw status
fi

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}Your application is now running at http://$(hostname -I | awk '{print $1}'):3025${NC}"
echo -e "${YELLOW}To check the status: pm2 status${NC}"
echo -e "${YELLOW}To view logs: pm2 logs jda_aistudio${NC}"

