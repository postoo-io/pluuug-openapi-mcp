"""pluuug-openapi-mcp — MCP server for pluuug openapi.

Wrapper around awslabs/openapi-mcp-server that sends pluuug's ``X-API-Key``
header and patches client-compatibility issues (outputSchema, stringified args).
"""

__version__ = "0.2.0"
