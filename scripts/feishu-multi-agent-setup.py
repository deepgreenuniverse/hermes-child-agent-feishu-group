#!/usr/bin/env python3
"""
飞书多 Agent 批量创建 - 一键启动器
用法: python3 feishu-multi-agent-setup.py
浏览器打开 http://127.0.0.1:8765

修复记录:
- v1.0 原版: API 路径 /oauth/v1/app_registration (下划线, 404)
- v1.1 修复: 改为 /oauth/v1/app/registration (斜杠, 正确)
- v1.2 修复: poll 添加 tp=ob_app 参数 (缺参数返回 20079 invalid_grant)
- v1.3 修复: import urllib.request (缺此导入则 AttributeError)
- v1.4 新增: 结果汇总复制区
- v1.5 修复: JS 独立成 /app.js，彻底规避 HTML 解析 </script> 截断问题
"""

import http.server, json, threading, urllib.parse, urllib.request, time, os
from http.server import HTTPServer

FEISHU_API = "https://accounts.feishu.cn/oauth/v1/app/registration"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APP_JS_PATH = os.path.join(SCRIPT_DIR, "app.js")

HTML = """<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>飞书多 Agent 批量创建</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; padding: 32px; }
h1 { font-size: 20px; font-weight: 600; color: #f8fafc; margin-bottom: 24px; }
.input-section { background: #1e293b; border-radius: 12px; padding: 24px; margin-bottom: 24px; border: 1px solid #334155; }
.input-section label { display: block; font-size: 14px; color: #94a3b8; margin-bottom: 12px; }
textarea { width: 100%; height: 120px; background: #0f172a; border: 1px solid #334155; border-radius: 8px; color: #e2e8f0; padding: 12px; font-size: 14px; resize: vertical; outline: none; }
textarea:focus { border-color: #3b82f6; }
textarea::placeholder { color: #475569; }
textarea[readonly] { resize: none; }
.controls { margin-top: 16px; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
button { padding: 10px 24px; border-radius: 8px; border: none; font-size: 14px; font-weight: 500; cursor: pointer; transition: all 0.15s; }
.btn-primary { background: #3b82f6; color: white; }
.btn-primary:hover { background: #2563eb; }
.btn-primary:disabled { background: #1e40af; color: #60a5fa; cursor: not-allowed; }
.btn-secondary { background: #334155; color: #cbd5e1; }
.btn-secondary:hover { background: #475569; }
.progress-info { font-size: 13px; color: #64748b; margin-left: 12px; }
.agents-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 16px; }
.agent-card { background: #1e293b; border-radius: 12px; padding: 20px; border: 2px solid #334155; transition: border-color 0.3s; }
.agent-card.active { border-color: #3b82f6; }
.agent-card.done { border-color: #22c55e; }
.agent-card.error { border-color: #ef4444; }
.agent-name { font-size: 15px; font-weight: 600; color: #f8fafc; margin-bottom: 8px; }
.agent-status { font-size: 12px; padding: 4px 10px; border-radius: 20px; display: inline-block; margin-bottom: 12px; }
.status-pending { background: #334155; color: #94a3b8; }
.status-waiting_scan { background: #1e3a5f; color: #93c5fd; }
.status-polling { background: #92400e; color: #fcd34d; }
.status-done { background: #14532d; color: #86efac; }
.status-error { background: #7f1d1d; color: #fca5a5; }
.qr-box { background: #0f172a; border-radius: 8px; padding: 16px; text-align: center; margin-bottom: 12px; }
.qr-box a { color: #60a5fa; font-size: 13px; text-decoration: none; word-break: break-all; display: block; margin: 4px 0; }
.qr-box a:hover { text-decoration: underline; }
.qr-hint { font-size: 12px; color: #64748b; margin: 8px 0 4px; }
.user-code { font-size: 20px; font-weight: 700; color: #f8fafc; letter-spacing: 3px; margin: 8px 0; }
.agent-creds { font-size: 12px; color: #94a3b8; background: #0f172a; border-radius: 6px; padding: 12px; word-break: break-all; }
.agent-creds div { margin: 4px 0; }
.agent-creds span { color: #64748b; }
.error-msg { font-size: 12px; color: #f87171; margin-top: 8px; background: #1e1e1e; padding: 8px; border-radius: 6px; }
.results-section .input-section { background: #1e293b; }
.results-textarea { height: 100px !important; color: #86efac !important; font-size: 13px !important; }
.log-box { background: #0f172a; border-radius: 8px; padding: 16px; margin-top: 24px; border: 1px solid #334155; font-family: 'Fira Code', monospace; font-size: 12px; color: #94a3b8; max-height: 200px; overflow-y: auto; }
.log-line { margin: 2px 0; }
.log-ts { color: #475569; margin-right: 8px; }
.log-ok { color: #86efac; }
.log-err { color: #f87171; }
.log-info { color: #60a5fa; }
</style>
</head>
<body>
<h1>🚀 飞书多 Agent 批量创建</h1>
<div class="input-section">
  <label>输入 Agent 名称（每行一个，按顺序处理）</label>
  <textarea id="agentNames" placeholder="alpha&#10;beta&#10;gamma"></textarea>
  <div class="controls">
    <button class="btn-primary" id="btnStart" onclick="startBatch()">▶ 开始批量创建</button>
    <button class="btn-secondary" id="btnReset" onclick="resetAll()">重置</button>
    <span class="progress-info" id="progressInfo"></span>
  </div>
</div>
<div class="agents-grid" id="agentsGrid"></div>
<div class="results-section" id="resultsSection" style="display:none; margin-top:24px;">
  <div class="input-section">
    <div class="controls" style="margin-bottom:12px;">
      <label style="color:#94a3b8;font-size:14px;">📋 批量凭证（完成后一键复制）</label>
      <button class="btn-secondary" onclick="copyResults()">📋 复制全部</button>
    </div>
    <textarea id="resultsText" class="results-textarea" readonly placeholder="完成后这里显示所有凭证，格式：【名称】\nappId=xxx\nappSecret=xxx"></textarea>
  </div>
</div>
<div class="log-box" id="logBox"></div>
<script src="/app.js"></script>
</body>
</html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.end_headers()
            self.wfile.write(HTML.encode())
            return

        if self.path == '/app.js':
            try:
                with open(APP_JS_PATH, 'rb') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/javascript; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.end_headers()
                self.wfile.write(content)
            except FileNotFoundError:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'// app.js not found')
            return

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if self.path == '/feishu/begin':
            data = urllib.parse.urlencode({
                'action': 'begin',
                'archetype': 'PersonalAgent',
                'auth_method': 'client_secret',
                'request_user_info': 'open_id tenant_brand'
            }).encode()
            req = urllib.request.Request(FEISHU_API, data=data, headers={'Content-Type': 'application/x-www-form-urlencoded'})
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    body = r.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(body)
            except urllib.error.HTTPError as e:
                body = e.read()
                self.send_response(e.code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(body)
            return

        if self.path == '/feishu/poll':
            length = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(length)
            d = json.loads(raw)
            dc = d.get('device_code', '')
            data = urllib.parse.urlencode({'action': 'poll', 'device_code': dc, 'tp': 'ob_app'}).encode()
            req = urllib.request.Request(FEISHU_API, data=data, headers={'Content-Type': 'application/x-www-form-urlencoded'})
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    body = r.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(body)
            except urllib.error.HTTPError as e:
                body = e.read()
                self.send_response(e.code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()

if __name__ == '__main__':
    PORT = 8765
    server = HTTPServer(('127.0.0.1', PORT), Handler)
    print(f"""╔═══════════════════════════════════════════════════╗
║     飞书多 Agent 批量创建                          ║
╠═══════════════════════════════════════════════════╣
║  🌐  浏览器打开:  http://127.0.0.1:{PORT}            ║
║  输入多个 Agent 名称，依次扫码，自动完成所有配置   ║
║  按 Ctrl+C 停止                                   ║
╚═══════════════════════════════════════════════════╝""")
    server.serve_forever()
