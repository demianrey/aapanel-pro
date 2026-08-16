#!/bin/bash
# Monitor plugin stub installer
# Creates the nginx log format file required for site creation

PANEL_PATH="/www/server/panel"
NGINX_CONF="$PANEL_PATH/vhost/nginx/0.monitor_log_format.conf"

if [ "$1" = "install" ]; then
    # Create the monitor log format used by aaPanel when creating new sites
    cat > "$NGINX_CONF" << 'NGINX_EOF'
log_format monitor '$remote_addr $server_port $ssl_protocol $http_host '
                   '$request_time $status $bytes_sent '
                   '"$http_referer" "$http_user_agent" '
                   '"$http_x_forwarded_for" $request_length '
                   '"$request_method $uri$is_args$args HTTP/$server_protocol"';
NGINX_EOF
    # Reload nginx if running
    nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || true
    echo "Monitor stub installed: nginx log format created."
fi

if [ "$1" = "uninstall" ]; then
    rm -f "$NGINX_CONF"
    nginx -s reload 2>/dev/null || true
fi

exit 0
