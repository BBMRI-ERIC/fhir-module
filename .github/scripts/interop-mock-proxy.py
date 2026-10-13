import base64, json, os, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

TASK_ID     = os.environ['MOCK_TASK_ID']
FOCUS_APP   = os.environ['FOCUS_APP_ID']
BODY_B64    = os.environ['BODY_B64']
PORT        = int(os.environ.get('MOCK_PROXY_PORT', '8082'))
RESULT_FILE = os.environ['RESULT_FILE']

task_served = False
result_done = threading.Event()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        global task_served
        if self.path.startswith('/v1/tasks'):
            if not task_served:
                task_served = True
                self.send_json(200, [{
                    "id":   TASK_ID,
                    "from": "mock-broker.local.test",
                    "to":   [FOCUS_APP],
                    "ttl":  "3600s",
                    "failure_strategy": {"retry": {"backoff_millisecs": 1000, "max_tries": 3}},
                    "metadata": {"project": "miabis"},
                    "body": BODY_B64,
                }])
            else:
                self.send_json(200, [])
        elif self.path == '/v1/health':
            self.send_json(200, {'status': 'ok'})
        else:
            self.send_json(404, {})

    def do_PUT(self):
        parts = self.path.strip('/').split('/')
        if len(parts) == 5 and parts[0]=='v1' and parts[1]=='tasks' and parts[3]=='results':
            self._handle_result()
        else:
            self.send_json(404, {})

    def do_POST(self): self.do_PUT()

    def _handle_result(self):
        length = int(self.headers.get('Content-Length', 0))
        raw    = self.rfile.read(length)
        self.send_json(201, {})
        try:
            env = json.loads(raw)
        except Exception:
            return
        # Focus sends an intermediate PUT with status="claimed" before the
        # actual result; skip it and wait for "succeeded" or "failed".
        status = env.get('status', '')
        if status not in ('succeeded', 'failed', 'perm-failed'):
            return
        count = -1  # default: parse error
        try:
            report = json.loads(base64.b64decode(env.get('body', '')).decode())
            if report.get('resourceType') == 'MeasureReport':
                count = report['group'][0]['population'][0]['count']
            elif report.get('resourceType') == 'OperationOutcome':
                count = -2  # Blaze/Focus returned an error
        except Exception:
            pass
        with open(RESULT_FILE, 'w') as f:
            f.write(str(count))
        result_done.set()

server = HTTPServer(('0.0.0.0', PORT), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
result_done.wait(timeout=60)
if not result_done.is_set():
    with open(RESULT_FILE, 'w') as f:
        f.write('-3')  # timeout
server.shutdown()
