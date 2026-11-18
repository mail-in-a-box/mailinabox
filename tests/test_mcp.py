#!/usr/bin/env python3
# Tests the MCP (Model Context Protocol) endpoint of the control panel by
# performing the MCP handshake and calling every tool.
#
# tests/test_mcp.py hostname emailaddress password
#
# where emailaddress and password are for an administrator account
# that does not have multi-factor authentication enabled.

import sys
import json
import base64
import ssl
import urllib.request
import urllib.error

if len(sys.argv) < 4:
	print("Usage: tests/test_mcp.py hostname emailaddress password")
	sys.exit(1)

host, emailaddress, pw = sys.argv[1:4]
url = f"https://{host}/admin/mcp"
credentials = base64.b64encode(f"{emailaddress}:{pw}".encode()).decode()

# Like the other tests, don't verify the TLS certificate so that this
# works against development boxes that have a self-signed certificate.
context = ssl.create_default_context()
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE

def post(message):
	headers = {
		"Authorization": "Basic " + credentials,
		"Content-Type": "application/json",
		"Accept": "application/json, text/event-stream",
	}
	req = urllib.request.Request(url, json.dumps(message).encode("utf8"), headers=headers) # noqa: S310 (url is always https)
	try:
		with urllib.request.urlopen(req, context=context) as response: # noqa: S310
			body = response.read().decode("utf8")
			return response.status, (json.loads(body) if body else None)
	except urllib.error.HTTPError as e:
		print(f"HTTP error {e.code}:", e.read().decode("utf8"))
		sys.exit(1)

def call(request_id, method, params=None):
	status, response = post({ "jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {} })
	if status != 200 or response.get("id") != request_id or "result" not in response:
		print(f"{method} failed:", response)
		sys.exit(1)
	return response["result"]

result = call(1, "initialize", {
	"protocolVersion": "2025-06-18",
	"capabilities": {},
	"clientInfo": { "name": "mailinabox-test", "version": "1.0" },
})
print("initialize is OK. Protocol version:", result["protocolVersion"])

status, response = post({ "jsonrpc": "2.0", "method": "notifications/initialized" })
if status != 202:
	print("notifications/initialized should return 202, got", status)
	sys.exit(1)
print("notifications/initialized is OK.")

call(2, "ping")
print("ping is OK.")

tools = call(3, "tools/list")["tools"]
print("tools/list is OK:", ", ".join(tool["name"] for tool in tools))

failed = False
for i, tool in enumerate(tools):
	result = call(4 + i, "tools/call", { "name": tool["name"], "arguments": {} })
	if result.get("isError"):
		print(f"{tool['name']} returned an error:", result["content"][0]["text"])
		failed = True
	else:
		print(f"{tool['name']} is OK ({len(result['content'][0]['text'])} characters).")

sys.exit(1 if failed else 0)
