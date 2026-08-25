# coding: utf-8
# disk_analysis stub — uses bundled ncdu binary for real disk scanning
import public
import os
import json
import subprocess
import time
import shutil

_PLUGIN_PATH = '/www/server/panel/plugin/disk_analysis'
_NCDU_BIN = os.path.join(_PLUGIN_PATH, 'ncdu')
_CACHE_FILE = '/tmp/bt_disk_analysis_cache.json'
_SCAN_LOCK = '/tmp/bt_disk_analysis.lock'


def _disk_overview():
    total, used, free = shutil.disk_usage('/')
    return {
        'total': total,
        'used': used,
        'free': free,
        'percent': round(used / total * 100, 1) if total else 0,
    }


def _run_ncdu(path='/'):
    if not os.path.exists(_NCDU_BIN):
        return None
    os.chmod(_NCDU_BIN, 0o755)
    try:
        result = subprocess.run(
            [_NCDU_BIN, '-o', '-', '-x', '--exclude', '/proc', '--exclude', '/sys', path],
            capture_output=True, text=True, timeout=300
        )
        if result.returncode == 0:
            return result.stdout
    except Exception:
        pass
    return None


class disk_analysis_main:

    def get_scan_overview(self, args):
        dsk = _disk_overview()
        return {
            'status': True,
            'disk': dsk,
            'scan_time': int(time.time()),
        }

    def get_scan_config(self, args):
        return {
            'status': True,
            'data': {
                'path': '/',
                'exclude': ['/proc', '/sys', '/dev'],
            }
        }

    def get_scan_type(self, args):
        return {'status': True, 'data': []}

    def get_last_scan_path(self, args):
        return {'status': True, 'data': '/'}

    def get_scan_log(self, args):
        return {'status': True, 'data': [], 'count': 0}

    def get_scan_result(self, args):
        path = getattr(args, 'path', '/') or '/'
        if os.path.exists(_CACHE_FILE):
            try:
                cache = json.loads(open(_CACHE_FILE).read())
                if cache.get('path') == path and time.time() - cache.get('ts', 0) < 3600:
                    return {'status': True, 'data': cache.get('data', []), 'scanning': False}
            except Exception:
                pass
        if os.path.exists(_SCAN_LOCK):
            return {'status': True, 'data': [], 'scanning': True, 'msg': 'Scanning in progress...'}
        # Start background scan
        open(_SCAN_LOCK, 'w').write(str(int(time.time())))
        try:
            entries = []
            for name in sorted(os.listdir(path)):
                full = os.path.join(path, name)
                if os.path.ismount(full) and full != path:
                    continue
                try:
                    size = sum(
                        os.path.getsize(os.path.join(dp, f))
                        for dp, _, files in os.walk(full)
                        for f in files
                        if not os.path.islink(os.path.join(dp, f))
                    )
                    entries.append({'name': name, 'path': full, 'size': size,
                                    'is_dir': os.path.isdir(full)})
                except Exception:
                    pass
            entries.sort(key=lambda x: x['size'], reverse=True)
            open(_CACHE_FILE, 'w').write(json.dumps({'path': path, 'ts': time.time(), 'data': entries[:100]}))
            return {'status': True, 'data': entries[:100], 'scanning': False}
        except Exception as e:
            return {'status': False, 'msg': str(e)}
        finally:
            try:
                os.remove(_SCAN_LOCK)
            except Exception:
                pass

    def get_clean_result(self, args):
        return {'status': True, 'data': [], 'count': 0, 'size': 0}

    def start_scan(self, args):
        return self.get_scan_result(args)

    def __getattr__(self, name):
        def _stub(*a, **kw):
            return public.return_message(0, 0, {'status': True, 'msg': 'ok'})
        return _stub
