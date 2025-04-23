#!/usr/bin/env python3
import base64
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

import yaml


class SubHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # 解析URL
        parsed_url = urlparse(self.path)
        if parsed_url.path == "/sub":
            # 获取配置参数
            query_params = parse_qs(parsed_url.query)
            config_base64 = query_params.get("config", [""])[0]

            try:
                # 解码配置
                config_yaml = base64.b64decode(config_base64).decode("utf-8")

                # 设置响应头
                self.send_response(200)
                self.send_header("Content-type", "text/plain; charset=utf-8")
                self.end_headers()

                # 返回配置
                self.wfile.write(config_yaml.encode("utf-8"))
            except Exception as e:
                self.send_response(400)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(f"Error: {str(e)}".encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()


def run(server_class=HTTPServer, handler_class=SubHandler, port=8000):
    server_address = ("", port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting server on port {port}")
    httpd.serve_forever()


if __name__ == "__main__":
    run()
