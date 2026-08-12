#!/bin/bash
# aaPanel Pro - Post-install: installs PHP/Nginx/MySQL/Redis/phpMyAdmin A-to-Z
# Run after panel is up and patched.
# Usage: bash post_install.sh [--all | --php | --stack | --plugins]

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
head_() { echo -e "${BLUE}[==]${NC} $*"; }

PANEL_DIR="/www/server/panel"
INSTALL_DIR="$PANEL_DIR/install"

# Detect package manager type (0=yum/rpm, 3=apt/deb)
if command -v apt-get &>/dev/null; then
    PKGTYPE=3
else
    PKGTYPE=0
fi

run_install() {
    local type="$1" sname="$2" version="$3"
    local logfile="/tmp/install_${sname}_${version}.log"
    info "Installing $sname $version ..."
    cd "$INSTALL_DIR"
    bash install_soft.sh "$type" "install" "$sname" "$version" > "$logfile" 2>&1 &
    local pid=$!
    local dots=0
    while kill -0 $pid 2>/dev/null; do
        printf "."
        dots=$((dots+1))
        [ $dots -eq 60 ] && echo && dots=0
        sleep 3
    done
    echo
    wait $pid && info "$sname $version installed." || warn "$sname $version install failed (check $logfile)"
}

# ─── Nginx ────────────────────────────────────────────────────────────────────
install_nginx() {
    head_ "Installing Nginx"
    if [ -f "/www/server/nginx/sbin/nginx" ]; then
        info "Nginx already installed, skipping."
    else
        run_install "$PKGTYPE" "nginx" "stable"
    fi
}

# ─── MySQL ────────────────────────────────────────────────────────────────────
install_mysql() {
    head_ "Installing MySQL 8.0"
    if [ -f "/www/server/mysql/bin/mysql" ]; then
        info "MySQL already installed, skipping."
    else
        run_install "$PKGTYPE" "mysql" "8.0"
    fi
}

# ─── PHP versions ─────────────────────────────────────────────────────────────
install_php() {
    head_ "Installing PHP versions"
    for ver in 56 70 71 72 73 74 80 81 82 83; do
        if [ -d "/www/server/php/$ver" ] && [ -f "/www/server/php/$ver/bin/php" ]; then
            info "PHP $ver already installed, skipping."
        else
            run_install "$PKGTYPE" "php" "$ver"
        fi
    done
}

# ─── phpMyAdmin ───────────────────────────────────────────────────────────────
install_phpmyadmin() {
    head_ "Installing phpMyAdmin"
    if [ -d "/www/server/phpmyadmin" ] && ls /www/server/phpmyadmin/phpmyadmin_* &>/dev/null; then
        info "phpMyAdmin already installed, skipping."
    else
        run_install "$PKGTYPE" "phpmyadmin" "5.2"
    fi
}

# ─── Redis ────────────────────────────────────────────────────────────────────
install_redis() {
    head_ "Installing Redis"
    if [ -f "/www/server/redis/bin/redis-server" ]; then
        info "Redis already installed, skipping."
    else
        run_install "$PKGTYPE" "redis" "stable"
    fi
}

# ─── Memcached ────────────────────────────────────────────────────────────────
install_memcached() {
    head_ "Installing Memcached"
    if command -v memcached &>/dev/null; then
        info "Memcached already installed, skipping."
    else
        run_install "$PKGTYPE" "memcached" "stable"
    fi
}

# ─── Pure-FTPd ────────────────────────────────────────────────────────────────
install_pureftpd() {
    head_ "Installing Pure-FTPd"
    if [ -f "/usr/sbin/pure-ftpd" ] || [ -f "/www/server/pure-ftpd/sbin/pure-ftpd" ]; then
        info "Pure-FTPd already installed, skipping."
    else
        run_install "$PKGTYPE" "pure-ftpd" "stable"
    fi
}

# ─── Plugin activation ────────────────────────────────────────────────────────
activate_plugins() {
    head_ "Activating panel plugins via API"
    PANEL_SOCK="/tmp/panel.sock"
    # Use panel API to install/activate plugins listed in plugin directory
    if [ -d "$PANEL_DIR/plugin" ]; then
        for plugin_dir in "$PANEL_DIR/plugin"/*/; do
            plugin_name=$(basename "$plugin_dir")
            if [ -f "$plugin_dir/install.sh" ]; then
                info "Running install for $plugin_name"
                cd "$plugin_dir"
                bash install.sh install 2>/dev/null || true
            fi
        done
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
MODE="${1:---all}"

case "$MODE" in
    --all)
        install_nginx
        install_mysql
        install_php
        install_phpmyadmin
        install_redis
        install_memcached
        install_pureftpd
        activate_plugins
        ;;
    --stack)
        install_nginx
        install_mysql
        install_php
        install_phpmyadmin
        install_redis
        ;;
    --php)
        install_php
        ;;
    --plugins)
        activate_plugins
        ;;
    --nginx)  install_nginx ;;
    --mysql)  install_mysql ;;
    --redis)  install_redis ;;
    --pma)    install_phpmyadmin ;;
    *)
        echo "Usage: $0 [--all|--stack|--php|--nginx|--mysql|--pma|--redis|--plugins]"
        echo "  --all     Install everything (PHP 5.6–8.3, Nginx, MySQL, phpMyAdmin, Redis, Memcached, FTP)"
        echo "  --stack   Core stack: Nginx + MySQL + PHP 5.6–8.3 + phpMyAdmin + Redis"
        echo "  --php     PHP versions only (5.6, 7.0-7.4, 8.0-8.3)"
        exit 1
        ;;
esac

info "Post-install complete."
