# Local SSE mock server for testing the streaming HTTP path (#4).
# Serves POST /v1/chat/completions with an OpenAI-style SSE stream.
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

CHUNKS = ["Hello", ", ", "stream", "ing", " world", "！"]  # includes multi-byte UTF-8

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        body = json.dumps({"echo_request_stream": True}).encode()
        if self.path == "/v1/chat/completions":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for i, text in enumerate(CHUNKS):
                frame = "data: " + json.dumps({
                    "choices": [{"delta": {"content": text}, "index": 0}]
                }) + "\n\n"
                self.wfile.write(frame.encode("utf-8"))
                self.wfile.flush()
            usage = "data: " + json.dumps({
                "choices": [{"delta": {}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 6}
            }) + "\n\n"
            self.wfile.write(usage.encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 18473), Handler)
    print("listening on 18473", flush=True)
    server.serve_forever()
