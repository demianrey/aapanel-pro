# coding: utf-8
import public
import os
import json

class btwaf_main:
    _plugin_path = '/www/server/panel/plugin/btwaf'

    def index(self, args):
        from flask import make_response
        html_file = self._plugin_path + '/index.html'
        if os.path.exists(html_file):
            return make_response(open(html_file).read(), 200, {'Content-Type': 'text/html; charset=utf-8'})
        return make_response('<p>WAF - not configured</p>', 200, {'Content-Type': 'text/html; charset=utf-8'})

    def get_total_all(self, args):
        return {'open': False, 'safe_day': 0, 'total': {'total': 0, 'rules': []}}

    def get_status(self, args):
        return {'open': False, 'status': True, 'msg': 'ok'}

    def set_open(self, args):
        return public.return_message(0, 0, 'ok')

    def get_config(self, args):
        # Frontend iterates overall_show_config keys against this dict
        return {}

    def set_config(self, args):
        return public.return_message(0, 0, 'ok')

    def get_site_config(self, args):
        return []

    def return_site(self, args):
        return []

    def get_gl_logs(self, args):
        return {'data': [], 'count': 0}

    def get_logs_list(self, args):
        return {'data': [], 'count': 0}

    def get_rule(self, args):
        return []

    def get_ua_white(self, args):
        return []

    def get_ua_black(self, args):
        return []

    def return_is_site(self, args):
        return []

    def get_url_find(self, args):
        return []

    def get_url_white_chekc(self, args):
        return []

    def get_site_rule(self, args):
        return []

    def get_history_logs(self, args):
        return {'data': [], 'count': 0}

    def __getattr__(self, name):
        def _stub(*a, **kw):
            return public.return_message(0, 0, {'status': True, 'msg': 'ok'})
        return _stub
