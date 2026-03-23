#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting update of JD Alchemy AI Studio...${NC}"

# Check if the repository exists
if [ ! -d "/root/jda_aistudio" ]; then
    echo -e "${YELLOW}Repository does not exist. Please run deploy.sh first.${NC}"
    exit 1
fi

# Navigate to the project directory
cd /root/jda_aistudio

# Pull the latest changes
echo -e "${GREEN}Pulling latest changes from the repository...${NC}"
git fetch

# Detect current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
CURRENT_COMMIT=$(git rev-parse HEAD)
LATEST_COMMIT=$(git rev-parse origin/${CURRENT_BRANCH} 2>/dev/null || git rev-parse origin/main)

if [ "$CURRENT_COMMIT" = "$LATEST_COMMIT" ]; then
    echo -e "${YELLOW}Already up to date. No changes to pull.${NC}"
else
    echo -e "${GREEN}New updates available. Updating...${NC}"
    
    # Stash any local changes if necessary
    git stash
    
    # Pull the latest changes
    git pull origin ${CURRENT_BRANCH} || git pull origin main
    
    # Install dependencies (in case there are new ones)
    echo -e "${GREEN}Installing npm dependencies...${NC}"
    npm install
    
    # Build the application
    echo -e "${GREEN}Building the application...${NC}"
    # Set Node.js memory limit and environment
    export NODE_OPTIONS="--max-old-space-size=2048"
    export NODE_ENV=production
    npm run build
    
    # Restart the application with PM2
    echo -e "${GREEN}Restarting the application with PM2...${NC}"
    pm2 restart jda_aistudio

    # Save PM2 configuration
    pm2 save
    
    echo -e "${GREEN}Update completed successfully!${NC}"
fi

echo -e "${YELLOW}Your application is running at http://$(hostname -I | awk '{print $1}'):3025${NC}"
echo -e "${YELLOW}To check the status: pm2 status${NC}"
echo -e "${YELLOW}To view logs: pm2 logs jda_aistudio${NC}"
