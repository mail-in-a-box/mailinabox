# Model Context Protocol (MCP) server for the Mail-in-a-Box control panel.
#
# MCP lets AI assistants (e.g. Claude Code, VS Code, Cursor) call "tools"
# on a server. This module implements the stateless form of MCP's
# "Streamable HTTP" transport: each HTTP POST carries one JSON-RPC 2.0
# message and gets back at most one JSON response. It is served by
# daemon.py at /admin/mcp, behind the same admin authentication as the
# rest of the management API.
#
# All tools are read-only and return the same information as the
# corresponding management API endpoints.
#
# Spec: https://modelcontextprotocol.io/specification

import io
import json
import multiprocessing.pool

from mailconfig import get_mail_users_ex, get_mail_aliases_ex
from status_checks import run_checks, FileOutput
from dns_update import build_recommended_dns
from backup import backup_status

# Protocol revisions we can speak, newest first. This server only uses
# the parts of the protocol that are the same in all of them.
PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26"]

# TOOLS

def get_status_checks(env):
	# Same checks as the control panel's System Status Checks page,
	# formatted as plain text like management/status_checks.py prints.
	output = FileOutput(io.StringIO(), None)
	with multiprocessing.pool.Pool(processes=5) as pool:
		run_checks(False, env, output, pool)
		pool.close()
		pool.join()
	return output.buf.getvalue()

def list_users(env):
	return get_mail_users_ex(env, with_archived=True)

def list_aliases(env):
	return get_mail_aliases_ex(env)

def get_dns_records(env):
	return build_recommended_dns(env)

def get_backup_status(env):
	return backup_status(env)

TOOLS = {
	"get_status_checks": (get_status_checks,
		"Run the box's system status checks: services, DNS, TLS certificates, "
		"blocklists, backups, disk space and software updates. Start here when "
		"diagnosing any problem. Can take a minute to run."),
	"list_users": (list_users,
		"List mail users grouped by domain, with their privileges, status and quota."),
	"list_aliases": (list_aliases,
		"List mail aliases grouped by domain, with their forwarding destinations "
		"and permitted senders."),
	"get_dns_records": (get_dns_records,
		"List the DNS records the box serves for each domain, with explanations. "
		"Useful when DNS is hosted elsewhere and records must be set at a registrar."),
	"get_backup_status": (get_backup_status,
		"Show the backups that exist, their sizes and dates, and any backup error."),
}

# JSON-RPC

def handle_request(message, env):
	# Process one JSON-RPC message from an MCP client. `message` is the
	# parsed request body, or None if it could not be parsed. Returns a
	# JSON-RPC response object, or None if no response should be sent
	# (for notifications and for responses sent to us by the client).

	if not isinstance(message, dict):
		return error_response(None, -32700, "Parse error: send a single JSON-RPC message object.")

	if "method" not in message or "id" not in message:
		return None

	request_id = message["id"]
	method = message["method"]
	params = message.get("params") or {}

	if method == "initialize":
		requested_version = params.get("protocolVersion")
		return result_response(request_id, {
			"protocolVersion": requested_version if requested_version in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
			"capabilities": { "tools": {} },
			"serverInfo": { "name": "mailinabox", "version": "1.0" },
			"instructions": f"These tools read the configuration and health of the Mail-in-a-Box mail server {env['PRIMARY_HOSTNAME']}. They cannot change anything.",
		})

	if method == "ping":
		return result_response(request_id, {})

	if method == "tools/list":
		return result_response(request_id, {
			"tools": [
				{
					"name": name,
					"description": description,
					"inputSchema": { "type": "object", "properties": {} },
					"annotations": { "readOnlyHint": True },
				}
				for name, (func, description) in TOOLS.items()
			]
		})

	if method == "tools/call":
		name = params.get("name")
		if name not in TOOLS:
			return error_response(request_id, -32602, f"Unknown tool: {name}")
		func = TOOLS[name][0]
		try:
			result = func(env)
		except Exception as e: # noqa: BLE001
			# Tool errors are reported to the AI as a result, not as a protocol error.
			return result_response(request_id, {
				"content": [{ "type": "text", "text": str(e) }],
				"isError": True,
			})
		if not isinstance(result, str):
			result = json.dumps(result, indent=2, sort_keys=True)
		return result_response(request_id, {
			"content": [{ "type": "text", "text": result }],
			"isError": False,
		})

	return error_response(request_id, -32601, f"Method not found: {method}")

def result_response(request_id, result):
	return { "jsonrpc": "2.0", "id": request_id, "result": result }

def error_response(request_id, code, message):
	return { "jsonrpc": "2.0", "id": request_id, "error": { "code": code, "message": message } }
