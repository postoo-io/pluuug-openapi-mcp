"""pluuug-openapi-mcp — MCP server for pluuug openapi with HMAC body signing.

Wrapper around awslabs/openapi-mcp-server that injects pluuug's required
X-API-Key + X-Signature (HMAC-SHA256 of request body) auth headers.
"""

__version__ = "0.1.0"
