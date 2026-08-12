#!/bin/bash
# aaPanel Pro - One-command patcher and post-installer
# Prerequisites: aaPanel must already be installed (bt panel must be running)
# To install aaPanel first: bash <(curl -s https://www.aapanel.com/script/install_7.0_en.sh)

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[!]${NC} $*"; exit 1; }

PANEL_DIR="/www/server/panel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check aaPanel is installed
# public.py is a single file in older versions and a package (class/public/) in aaPanel 7.x
if [ ! -f "$PANEL_DIR/class/public.py" ] && [ ! -d "$PANEL_DIR/class/public" ] && [ ! -f "$PANEL_DIR/tools.py" ]; then
    error "aaPanel not found. Install it first: bash <(curl -s https://www.aapanel.com/script/install_7.0_en.sh)"
fi

# Apply pro patches
info "Applying pro patches..."
bash "$SCRIPT_DIR/patch.sh"

# Restart panel
info "Restarting panel..."
bt restart 2>/dev/null || true

info "Done! Run: bash post_install.sh --all  (installs PHP/Nginx/MySQL/phpMyAdmin/Redis)"
