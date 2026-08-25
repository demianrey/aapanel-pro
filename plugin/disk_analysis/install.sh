#!/bin/bash
# disk_analysis stub installer
PLUGIN_PATH="/www/server/panel/plugin/disk_analysis"

if [ "$1" = "install" ]; then
    chmod +x "$PLUGIN_PATH/ncdu" 2>/dev/null || true
    ln -sf "$PLUGIN_PATH/ncdu" /usr/bin/ncdu 2>/dev/null || true
    echo "disk_analysis stub installed."
fi

if [ "$1" = "uninstall" ]; then
    rm -f /usr/bin/ncdu
    rm -rf "$PLUGIN_PATH"
fi

exit 0
