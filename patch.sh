#!/bin/bash
# aaPanel Pro - Patch script
# Applies DRM bypass and frontend unlocks to any aaPanel installation
# Safe to re-run — idempotent

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

PANEL_DIR="/www/server/panel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASS_DIR="$PANEL_DIR/class"
VITE_JS_DIR="$PANEL_DIR/BTPanel/static/vite/js"

[ -d "$CLASS_DIR" ] || { echo "aaPanel not found at $PANEL_DIR"; exit 1; }

# ─── 1. Stop panel ────────────────────────────────────────────────────────────
info "Stopping panel..."
bt stop 2>/dev/null || true

# ─── 2. Install PluginLoader bypass ──────────────────────────────────────────
info "Installing PluginLoader bypass..."

# Back up the original .so as PluginLoader_real.so (used by the Python mock)
if [ ! -f "$CLASS_DIR/PluginLoader_real.so" ]; then
    ARCH=$(uname -m)
    PY_VER=$("$PANEL_DIR/pyenv/bin/python3" -c "import sys; print('Python{}.{}'.format(*sys.version_info[:2]))" 2>/dev/null || echo "Python3.12")
    for so in \
        "$SCRIPT_DIR/so/PluginLoader.${ARCH}.${PY_VER}.so" \
        "$SCRIPT_DIR/so/PluginLoader.${ARCH}.glibc214.${PY_VER}.so" \
        "$CLASS_DIR/PluginLoader.${ARCH}.${PY_VER}.so" \
        "$CLASS_DIR/PluginLoader.${ARCH}.glibc214.${PY_VER}.so"; do
        if [ -f "$so" ]; then
            cp "$so" "$CLASS_DIR/PluginLoader_real.so"
            info "Backed up: $(basename $so) → PluginLoader_real.so"
            break
        fi
    done
fi

# Copy all .so variants from repo into class dir
if [ -d "$SCRIPT_DIR/so" ]; then
    cp -f "$SCRIPT_DIR/so/"*.so "$CLASS_DIR/" 2>/dev/null || true
fi

# Install the Python mock (overrides .so, patches all plugin endtimes to pro)
cp -f "$SCRIPT_DIR/patches/PluginLoader.py" "$CLASS_DIR/PluginLoader.py"
info "PluginLoader.py bypass installed."

# Remove PluginLoader.so — BT-Panel recreates it on each start, overriding our .py bypass.
# We use sitecustomize.py (runs before any panel code) to delete it again on each Python start.
rm -f "$CLASS_DIR/PluginLoader.so"
SITECUSTOMIZE="$PANEL_DIR/pyenv/lib/python3.12/site-packages/sitecustomize.py"
cat > "$SITECUSTOMIZE" << 'SCEOF'
# aaPanel Pro bypass — runs before any panel code via Python's sitecustomize hook.
# Deletes PluginLoader.so each time Python starts so PluginLoader.py takes priority.
import sys, os

_pro_dir = '/www/server/panel/class'
_py_bypass = os.path.join(_pro_dir, 'PluginLoader.py')

if os.path.exists(_py_bypass):
    if _pro_dir in sys.path:
        sys.path.remove(_pro_dir)
    sys.path.insert(0, _pro_dir)

_so = os.path.join(_pro_dir, 'PluginLoader.so')
if os.path.exists(_so):
    try:
        os.remove(_so)
    except Exception:
        pass
SCEOF
info "sitecustomize.py installed (PluginLoader.so auto-deleted on panel start)."

# ─── 3. Patch frontend JS files (version-agnostic) ───────────────────────────
info "Patching frontend JS..."

python3 << 'PYEOF'
import os, re, sys

vite_dir = "/www/server/panel/BTPanel/static/vite/js"
if not os.path.isdir(vite_dir):
    print("WARN: vite/js dir not found")
    sys.exit(0)

# Each entry: (regex_pattern, replacement_fn, description)
# Using regex so we match regardless of the minified variable name (md=, Rd=, At=, etc.)
PATCHES = [
    # App Store buy indicator (arrow function) — always return false
    (
        r'(\w+=e=>e\.price!==[`"])0\.00[`"]\&\&\(e\.endtime==-1\|\|e\.endtime==-2\),',
        lambda m: m.group(1).split('=e=>')[0] + '=e=>!1,',
        'App Store buy indicator (arrow fn) disabled'
    ),
    # App Store buy indicator (regular function, legacy bundle)
    (
        r'(\w+=function\(e\)\{return e\.price!==[`"])0\.00[`"]\&\&\(e\.endtime==-1\|\|e\.endtime==-2\)\}',
        lambda m: m.group(0).split('=function')[0] + '=function(e){return!1}',
        'App Store buy indicator (legacy fn) disabled'
    ),
    # WAF install page — always show Install button (not Buy)
    (
        r't\(v\)\?\(p\(\),r\(m,\{key:0,type:"primary",class:"text-14px",onClick:h\}',
        lambda m: '(!0)?(p(),r(m,{key:0,type:"primary",class:"text-14px",onClick:h}',
        'WAF install page: Install button always shown'
    ),
]

applied = already = 0
for fname in sorted(os.listdir(vite_dir)):
    if not fname.endswith('.js'):
        continue
    fpath = os.path.join(vite_dir, fname)
    try:
        with open(fpath, 'r', errors='replace') as f:
            content = f.read()
        modified = False
        for pattern, repl, desc in PATCHES:
            new_content = re.sub(pattern, repl, content)
            if new_content != content:
                content = new_content
                modified = True
                print(f"  [+] {desc} ({fname})")
                applied += 1
            elif re.search(pattern.replace(r'(\w+=e=>e\.price!==', r'(\w+=e=>!1').replace(r'(\w+=function\(e\)\{return e\.price!==', r'(\w+=function\(e\)\{return!1'), content):
                already += 1
        if modified:
            with open(fpath, 'w') as f:
                f.write(content)
    except Exception as e:
        print(f"  [!] {fname}: {e}")

if applied == 0 and already > 0:
    print("  [+] All JS patches already applied.")
elif applied == 0:
    print("  [!] Warning: no JS patterns matched. Check vite JS filenames/patterns.")
PYEOF

# ─── 4. Patch panelPlugin.py — CDN fallback for paid plugin downloads ────────
info "Patching panelPlugin.py (CDN download fallback)..."

python3 << 'PYEOF'
import re, sys

PP = '/www/server/panel/class/panelPlugin.py'

with open(PP, 'r') as f:
    content = f.read()

MARKER = '# _pro_cdn_fallback'
if MARKER in content:
    print("  [+] panelPlugin.py CDN fallback already applied.")
    sys.exit(0)

OLD = "            return self.__install_plugin(pluginInfo['name'], get.version)\n"
NEW = """\
            _result = self.__install_plugin(pluginInfo['name'], get.version) # _pro_cdn_fallback
            if isinstance(_result, dict):
                _msg = str(_result.get('msg', '')) + str(_result.get('res', ''))
                if 'authorization' in _msg or 'not have' in _msg:
                    _sh_url = None
                    _cdn = 'https://node.aapanel.com'
                    for _suf in ['_en', '']:
                        _u = '{}/install/plugin/{}{}/install.sh'.format(_cdn, pluginInfo['name'], _suf)
                        try:
                            import requests as _rq
                            if _rq.head(_u, timeout=8, verify=False).status_code == 200:
                                _sh_url = _u
                                break
                        except: pass
                    if _sh_url:
                        # Build a temp dir so input_zip can proceed normally.
                        # The wrapper install.sh runs the real CDN script in the background,
                        # returning immediately so input_zip doesn't block.
                        _tmp = self.__tmp_path + pluginInfo['name']
                        if not os.path.exists(_tmp): os.makedirs(_tmp, mode=0o755)
                        # Wrapper install.sh: download + run CDN script in background
                        _wrap = ('#!/bin/bash\\n'
                                 'wget -q --no-check-certificate -O /tmp/bt_{n}_real.sh {url} -T 60\\n'
                                 'nohup bash /tmp/bt_{n}_real.sh "$1" > /tmp/panelExec.log 2>&1 &\\n'
                                 ).format(n=pluginInfo['name'], url=_sh_url)
                        with open(os.path.join(_tmp, 'install.sh'), 'w') as _f: _f.write(_wrap)
                        os.chmod(os.path.join(_tmp, 'install.sh'), 0o755)
                        # Try to fetch real info.json from CDN
                        _info = None
                        try:
                            _ir = _rq.get('{}/install/plugin/{}_en/info.json'.format(_cdn, pluginInfo['name']), timeout=6)
                            if _ir.status_code == 200: _info = _ir.json()
                        except: pass
                        if not _info:
                            _pv = pluginInfo['versions'][0] if pluginInfo.get('versions') else {}
                            _info = {'name': pluginInfo['name'],
                                     'title': pluginInfo.get('title', pluginInfo['name']),
                                     'versions': _pv.get('full_version', _pv.get('m_version', '1.0')),
                                     'author': 'aapanel', 'home': 'https://www.aapanel.com'}
                        with open(os.path.join(_tmp, 'info.json'), 'w') as _f:
                            import json as _json; _f.write(_json.dumps(_info))
                        _info['tmp_path'] = _tmp
                        _info['old_version'] = '0'
                        _info['size'] = public.get_path_size(_tmp)
                        _info['dependent'] = self.__check_dependent(pluginInfo['name'])
                        _info['update_msg'] = ''
                        _info['install_opt'] = 'i'
                        if os.path.exists('/tmp/panelExec.log'):
                            open('/tmp/panelExec.log', 'w').write('')
                        return _info
            return _result
"""

if OLD not in content:
    print("  [!] Could not find install_sync return line in panelPlugin.py — skipping.")
    sys.exit(0)

content = content.replace(OLD, NEW, 1)
with open(PP, 'w') as f:
    f.write(content)
print("  [+] panelPlugin.py patched: CDN fallback added to install_sync.")
PYEOF

# ─── 5. Patch panel_plugin_v2.py — CDN fallback for v2 API route ─────────────
info "Patching panel_plugin_v2.py (CDN download fallback)..."

python3 << 'PYEOF'
import re, sys

PP = '/www/server/panel/class_v2/panel_plugin_v2.py'

with open(PP, 'r') as f:
    content = f.read()

MARKER = '# _pro_cdn_fallback'
if MARKER in content:
    print("  [+] panel_plugin_v2.py CDN fallback already applied.")
    sys.exit(0)

# The v2 install_sync uses get.get('version', '') instead of get.version
OLD = "            _result = self.__install_plugin(pluginInfo['name'], get.get('version', ''))\n"
NEW = """\
            _result = self.__install_plugin(pluginInfo['name'], get.get('version', '')) # _pro_cdn_fallback
            if isinstance(_result, dict):
                _msg = str(_result.get('msg', '')) + str(_result.get('res', ''))
                if 'authorization' in _msg or 'not have' in _msg:
                    _sh_url = None
                    _cdn = 'https://node.aapanel.com'
                    for _suf in ['_en', '']:
                        _u = '{}/install/plugin/{}{}/install.sh'.format(_cdn, pluginInfo['name'], _suf)
                        try:
                            import requests as _rq
                            if _rq.head(_u, timeout=8, verify=False).status_code == 200:
                                _sh_url = _u
                                break
                        except: pass
                    if _sh_url:
                        _tmp = self.__tmp_path + pluginInfo['name']
                        if not os.path.exists(_tmp): os.makedirs(_tmp, mode=0o755)
                        _wrap = ('#!/bin/bash\\n'
                                 'wget -q --no-check-certificate -O /tmp/bt_{n}_real.sh {url} -T 60\\n'
                                 'nohup bash /tmp/bt_{n}_real.sh "$1" > /tmp/panelExec.log 2>&1 &\\n'
                                 ).format(n=pluginInfo['name'], url=_sh_url)
                        with open(os.path.join(_tmp, 'install.sh'), 'w') as _f: _f.write(_wrap)
                        os.chmod(os.path.join(_tmp, 'install.sh'), 0o755)
                        _info = None
                        try:
                            _ir = _rq.get('{}/install/plugin/{}_en/info.json'.format(_cdn, pluginInfo['name']), timeout=6)
                            if _ir.status_code == 200: _info = _ir.json()
                        except: pass
                        if not _info:
                            _pv = pluginInfo['versions'][0] if pluginInfo.get('versions') else {}
                            _info = {'name': pluginInfo['name'],
                                     'title': pluginInfo.get('title', pluginInfo['name']),
                                     'versions': _pv.get('full_version', _pv.get('m_version', '1.0')),
                                     'author': 'aapanel', 'home': 'https://www.aapanel.com'}
                        with open(os.path.join(_tmp, 'info.json'), 'w') as _f:
                            import json as _json; _f.write(_json.dumps(_info))
                        _info['tmp_path'] = _tmp
                        _info['old_version'] = '0'
                        _info['size'] = public.get_path_size(_tmp)
                        _info['dependent'] = {}
                        _info['update_msg'] = ''
                        _info['install_opt'] = 'i'
                        if os.path.exists('/tmp/panelExec.log'):
                            open('/tmp/panelExec.log', 'w').write('')
                        return _info
            return _result
"""

if OLD not in content:
    # Try without leading spaces (direct return form)
    OLD2 = "        return self.__install_plugin(pluginInfo['name'], get.get('version', ''))\n"
    if OLD2 in content:
        OLD = OLD2
        # Re-indent entire NEW block from 12-space base to 8-space base
        new_lines = []
        for _line in NEW.split('\n'):
            if _line.startswith('            '):
                _line = '        ' + _line[12:]
            new_lines.append(_line)
        NEW = '\n'.join(new_lines)
    else:
        print("  [!] Could not find install_sync return line in panel_plugin_v2.py — skipping.")
        sys.exit(0)

content = content.replace(OLD, NEW, 1)
with open(PP, 'w') as f:
    f.write(content)
print("  [+] panel_plugin_v2.py patched: CDN fallback added to install_sync.")
PYEOF

# ─── 6. Install paid plugins from CDN/stubs ───────────────────────────────────
info "Installing plugins..."

PLUGIN_DIR="$PANEL_DIR/plugin"
mkdir -p "$PLUGIN_DIR"

# btapp — download directly from CDN (simple file download, no compilation)
if [ ! -f "$PLUGIN_DIR/btapp/info.json" ]; then
    info "  Installing btapp from CDN..."
    wget -q --no-check-certificate -O /tmp/bt_btapp_install.sh \
        https://node.aapanel.com/install/plugin/btapp_en/install.sh -T 30 && \
    bash /tmp/bt_btapp_install.sh install 2>/dev/null && \
    cp -f "$PLUGIN_DIR/btapp/icon.png" "$PANEL_DIR/BTPanel/static/img/soft_ico/ico-btapp.png" 2>/dev/null || true
    [ -f "$PLUGIN_DIR/btapp/info.json" ] && info "  btapp installed." || warn "  btapp install failed."
fi
# Always overwrite btapp with our patched files (QR fix + version 1.2)
if [ -f "$PLUGIN_DIR/btapp/info.json" ] && [ -d "$SCRIPT_DIR/plugin/btapp" ]; then
    cp -f "$SCRIPT_DIR/plugin/btapp/info.json" "$PLUGIN_DIR/btapp/info.json"
    cp -f "$SCRIPT_DIR/plugin/btapp/index.html" "$PLUGIN_DIR/btapp/index.html"
    info "  btapp patched files applied (v1.2 + QR fix)."
fi

# btwaf — extract from CDN zip, use stub main module (zip's .so is for Python 3.7)
if [ ! -f "$PLUGIN_DIR/btwaf/info.json" ]; then
    info "  Installing btwaf from CDN..."
    wget -q --no-check-certificate -O /tmp/btwaf.zip \
        https://node.aapanel.com/install/plugin/btwaf_en/btwaf.zip -T 60 && \
    unzip -q -o /tmp/btwaf.zip -d "$PLUGIN_DIR/" && rm -f /tmp/btwaf.zip
    # Replace empty btwaf_main.py with working stub (zip's .so is Python 3.7-only)
    if [ -f "$SCRIPT_DIR/plugin/btwaf/btwaf_main.py" ]; then
        cp -f "$SCRIPT_DIR/plugin/btwaf/btwaf_main.py" "$PLUGIN_DIR/btwaf/btwaf_main.py"
    fi
    # Set up WAF rule/data directories
    mkdir -p /www/server/btwaf/{inc,rule,html}
    cp -r "$PLUGIN_DIR/btwaf/btwaf_lua/rule" /www/server/btwaf/ 2>/dev/null || true
    cp "$PLUGIN_DIR/btwaf/btwaf_lua/html"/*.html /www/server/btwaf/html/ 2>/dev/null || true
    cp "$PLUGIN_DIR/btwaf/btwaf_lua/html/fingerprint2.js" /www/server/btwaf/html/ 2>/dev/null || true
    cp "$PLUGIN_DIR/btwaf/btwaf_lua"/*.lua /www/server/btwaf/ 2>/dev/null || true
    cp "$PLUGIN_DIR/btwaf/btwaf_lua/config.json" /www/server/btwaf/ 2>/dev/null || true
    cp "$PLUGIN_DIR/btwaf/btwaf_lua/domains.json" /www/server/btwaf/ 2>/dev/null || true
    cp -f "$PLUGIN_DIR/btwaf/icon.png" "$PANEL_DIR/BTPanel/static/img/soft_ico/ico-btwaf.png" 2>/dev/null || true
    [ -f "$PLUGIN_DIR/btwaf/info.json" ] && info "  btwaf installed." || warn "  btwaf install failed."
else
    info "  btwaf already installed."
fi

# monitor — use repo stub (no CDN install.sh available)
if [ ! -f "$PLUGIN_DIR/monitor/info.json" ]; then
    info "  Installing monitor stub..."
    if [ -d "$SCRIPT_DIR/plugin/monitor" ]; then
        mkdir -p "$PLUGIN_DIR/monitor"
        cp -f "$SCRIPT_DIR/plugin/monitor/"* "$PLUGIN_DIR/monitor/"
        bash "$PLUGIN_DIR/monitor/install.sh" install 2>/dev/null || true
        info "  monitor stub installed."
    else
        warn "  monitor stub not found in repo."
    fi
else
    info "  monitor already installed."
fi

# Clean temp dir
rm -rf "$PANEL_DIR/temp/"* 2>/dev/null || true

# ─── 7. Start panel ───────────────────────────────────────────────────────────
info "Starting panel..."
bt start 2>/dev/null || true

info "All patches applied."
