#!/usr/bin/env python3
import argparse
import base64
import json
from urllib.parse import quote

import qrcode


def load_config(config_path):
    with open(config_path, "r") as f:
        return json.load(f)


def generate_ss_url(config, server_ip):
    method = config["method"]
    password = config["password"]
    port = config["server_port"]

    # 构建SS URL
    ss_url = f"{method}:{password}@{server_ip}:{port}"
    encoded = base64.b64encode(ss_url.encode()).decode()
    return f"ss://{encoded}"


def generate_clash_config(config, server_ip):
    clash_config = {
        "proxies": [
            {
                "name": "Shadowsocks",
                "type": "ss",
                "server": server_ip,
                "port": config["server_port"],
                "cipher": config["method"],
                "password": config["password"],
            }
        ],
        "proxy-groups": [
            {"name": "PROXY", "type": "select", "proxies": ["Shadowsocks"]}
        ],
        "rules": ["MATCH,PROXY"],
    }
    return clash_config


def main():
    parser = argparse.ArgumentParser(
        description="Generate Shadowsocks QR code and links"
    )
    parser.add_argument(
        "--config", default="../config/config.json", help="Path to config file"
    )
    parser.add_argument("--server", required=True, help="Server IP address")
    parser.add_argument("--output", default="ss_qr.png", help="Output QR code file")
    args = parser.parse_args()

    config = load_config(args.config)

    # 生成SS URL
    ss_url = generate_ss_url(config, args.server)
    print(f"\nShadowsocks URL: {ss_url}")

    # 生成二维码
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(ss_url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(args.output)
    print(f"QR code saved to: {args.output}")

    # 生成Clash配置
    clash_config = generate_clash_config(config, args.server)
    clash_yaml = f"""mixed-port: 7890
allow-lan: true
mode: rule
log-level: info

proxies:
  - name: Shadowsocks
    type: ss
    server: {args.server}
    port: {config['server_port']}
    cipher: {config['method']}
    password: {config['password']}

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - Shadowsocks

rules:
  - MATCH,PROXY"""

    print("\nClash Verge 配置:")
    print(clash_yaml)

    # 保存Clash配置
    with open("clash_config.yaml", "w") as f:
        f.write(clash_yaml)
    print("\nClash配置已保存到: clash_config.yaml")


if __name__ == "__main__":
    main()
