# coding: utf-8
# Mock PluginLoader — overrides the .so files found by Python in this directory.
# Delegates all real functionality to the actual .so, but always returns
# authenticated/pro state for auth checks and fixes endtime for all plugins.

import sys
import os
import time
import importlib
import importlib.util
import platform

_PRO_EXPIRY = int(time.time()) + 10 * 365 * 24 * 3600  # 10 years
_PANEL_PATH = '/www/server/panel'
_AES_KEY = 'aapanel_bypass_k'  # 16-char fixed key, used only if real SO unavailable
_real = None  # the real PluginLoader .so module


def _load_real_so():
    global _real
    if _real is not None:
        return _real

    machine = platform.machine()        # x86_64, aarch64, i686, loongarch64
    py_ver = 'Python{}.{}'.format(*sys.version_info[:2])

    so_dir = os.path.join(_PANEL_PATH, 'class')
    if not os.path.isdir(so_dir):
        so_dir = os.path.dirname(os.path.abspath(__file__))

    candidates = [
        # renamed copy takes priority
        os.path.join(so_dir, 'PluginLoader_real.so'),
        os.path.join(so_dir, 'PluginLoader.{}.{}.so'.format(machine, py_ver)),
        os.path.join(so_dir, 'PluginLoader.{}.glibc214.{}.so'.format(machine, py_ver)),
    ]
    major, minor = sys.version_info[:2]
    for m in range(minor - 1, max(minor - 4, 6), -1):
        candidates.append(
            os.path.join(so_dir, 'PluginLoader.{}.Python{}.{}.so'.format(machine, major, m))
        )

    for path in candidates:
        if not os.path.exists(path):
            continue
        try:
            # C extensions require the module name to match PyInit_<name>.
            # The real SO exports PyInit_PluginLoader, so we must load it as
            # 'PluginLoader'. After exec_module the SO registers itself in
            # sys.modules['PluginLoader'], shadowing us — we restore our own
            # module object immediately afterwards.
            _self = sys.modules.get('PluginLoader')
            spec = importlib.util.spec_from_file_location('PluginLoader', path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            # Restore our .py so future 'import PluginLoader' returns our bypass
            if _self is not None:
                sys.modules['PluginLoader'] = _self
            else:
                sys.modules.pop('PluginLoader', None)
            _real = mod
            return _real
        except Exception:
            continue

    return None


def _patch_plugin_list(data):
    """Patch a plugin list dict: set pro/ltd to _PRO_EXPIRY, fix all endtime < 0."""
    if not isinstance(data, dict):
        return data
    data['pro'] = 0   # 0 = lifetime license (isLifetime=true in frontend)
    data['ltd'] = -1  # -1 = no enterprise license
    data['status'] = True
    plugin_list = data.get('list', [])
    for p in plugin_list:
        if not isinstance(p, dict):
            continue
        et = p.get('endtime')
        if et is None or (isinstance(et, (int, float)) and et < 0):
            p['endtime'] = _PRO_EXPIRY
        if p.get('authorization_sn') is None:
            p['authorization_sn'] = 'bypass_pro'
    return data


# ── Auth overrides — always return pro ──────────────────────────────────────

def get_auth_state():
    return 1


def get_plugin_list(force=0):
    real = _load_real_so()
    if real and hasattr(real, 'get_plugin_list'):
        try:
            data = real.get_plugin_list(force)
            return _patch_plugin_list(data)
        except Exception:
            pass
    return _patch_plugin_list({
        'pro': _PRO_EXPIRY,
        'ltd': _PRO_EXPIRY,
        'status': True,
        'msg': 'ok',
        'success': True,
        'list': [],
    })


def parse_plugin_list(force=0):
    return True


# ── Everything else — delegate to real SO, fall back to stubs ────────────────

def get_module(filename):
    real = _load_real_so()
    if real and hasattr(real, 'get_module'):
        try:
            result = real.get_module(filename)
            # Only return the real SO's result if it's an actual module, not an error dict
            if result is not None and not isinstance(result, dict):
                return result
        except Exception:
            pass
    # Raw fallback — load directly without any auth check
    try:
        if not os.path.exists(filename):
            return None
        spec = importlib.util.spec_from_file_location(
            '_pl_' + os.path.splitext(os.path.basename(filename))[0], filename
        )
        if not spec:
            return None
        mod = importlib.util.module_from_spec(spec)
        for p in ['/www/server/panel/class', '/www/server/panel/class_v2']:
            if p not in sys.path:
                sys.path.insert(0, p)
        spec.loader.exec_module(mod)
        return mod
    except Exception as e:
        return {'status': False, 'msg': str(e)}


def plugin_run(plugin_name, def_name, args):
    # Do NOT delegate to the real SO — it performs its own auth check against
    # the encrypted plugin_bin.pl and returns "unpaid or authorization expired"
    # for any plugin not covered by a real license.  Load the plugin directly.
    plugin_dir = os.path.join(_PANEL_PATH, 'plugin', plugin_name)
    candidates = [
        # Standard naming convention: {name}_main.py with class {name}_main
        (os.path.join(plugin_dir, '{}_main.py'.format(plugin_name)), '{}_main'.format(plugin_name)),
        # Legacy: index.py with class main
        (os.path.join(plugin_dir, 'index.py'), 'main'),
        # Alternate: {name}.py with class {name}
        (os.path.join(plugin_dir, '{}.py'.format(plugin_name)), plugin_name),
    ]
    for candidate, cls_name in candidates:
        if not os.path.exists(candidate):
            continue
        try:
            mod = get_module(candidate)
            if not mod or isinstance(mod, dict):
                continue
            cls = getattr(mod, cls_name, None)
            if cls is None:
                # Try any class in the module that has the method
                for attr in dir(mod):
                    obj_cls = getattr(mod, attr, None)
                    if isinstance(obj_cls, type):
                        cls = obj_cls
                        break
            if cls is None:
                continue
            obj = cls()
            method = getattr(obj, def_name, None)
            if method is None and hasattr(obj, '__getattr__'):
                method = getattr(obj, def_name)
            if method:
                return method(args)
        except Exception:
            pass
    # Return an error dict (not None) so callers that do result.get(...) don't crash
    return {'status': False, 'msg': 'plugin not found or load error: {}'.format(plugin_name)}


def module_run(module_name, def_name, args):
    real = _load_real_so()
    if real and hasattr(real, 'module_run'):
        try:
            return real.module_run(module_name, def_name, args)
        except Exception:
            pass
    try:
        for base in ['class_v2', 'class']:
            mod_file = os.path.join(_PANEL_PATH, base, '{}.py'.format(module_name))
            if os.path.exists(mod_file):
                mod = get_module(mod_file)
                if mod and not isinstance(mod, dict) and hasattr(mod, 'main'):
                    obj = mod.main()
                    if hasattr(obj, def_name):
                        return getattr(obj, def_name)(args)
    except Exception:
        pass
    return None


def _get_aes():
    try:
        sys.path.insert(0, os.path.join(_PANEL_PATH, 'class'))
        from panelAes import aescrypt_py3
        return aescrypt_py3(_AES_KEY)
    except Exception:
        return None


def db_encrypt(data):
    real = _load_real_so()
    if real and hasattr(real, 'db_encrypt'):
        try:
            return real.db_encrypt(data)
        except Exception:
            pass
    try:
        aes = _get_aes()
        if aes:
            return {'status': True, 'msg': aes.aesencrypt(str(data))}
    except Exception:
        pass
    return {'status': True, 'msg': data}


def db_decrypt(data):
    real = _load_real_so()
    if real and hasattr(real, 'db_decrypt'):
        try:
            return real.db_decrypt(data)
        except Exception:
            pass
    try:
        aes = _get_aes()
        if aes:
            return {'status': True, 'msg': aes.aesdecrypt(str(data))}
    except Exception:
        pass
    return {'status': True, 'msg': data}


def py_clear(*args, **kwargs):
    real = _load_real_so()
    if real and hasattr(real, 'py_clear'):
        try:
            return real.py_clear(*args, **kwargs)
        except Exception:
            pass
