# Infrastructure MCP Server

An MCP (Model Context Protocol) server that enables AI assistants to analyze codebases and generate infrastructure configurations for the Infrastructure Self-Service Platform.

## Features

- **Analyze Codebases**: Scans code for database connections, storage usage, frameworks, and environment variables to detect infrastructure needs
- **List Available Modules**: Shows all Terraform modules with their configuration options
- **Generate YAML**: Creates valid `infrastructure.yaml` files for the GitOps workflow
- **Validate Configurations**: Checks YAML against the schema and available modules

## Installation

```bash
cd mcp-server
npm install
npm run build
```

## Configuration

### For Claude Code

Add to your Claude Code MCP settings (`~/.claude/claude_desktop_config.json` or project settings):

```json
{
  "mcpServers": {
    "infrastructure": {
      "command": "node",
      "args": ["/path/to/infrastructure-automation/mcp-server/dist/index.js"]
    }
  }
}
```

### For Claude Desktop

Add to your Claude Desktop config:

```json
{
  "mcpServers": {
    "infrastructure": {
      "command": "node",
      "args": ["/path/to/infrastructure-automation/mcp-server/dist/index.js"]
    }
  }
}
```

## Available Tools

### `list_available_modules`

List all available Terraform modules with their configuration options.

```
Arguments:
  verbose: boolean (optional) - Include detailed config options
```

Example response:
```json
[
  {
    "name": "storage_account",
    "description": "Azure Storage Account for blob, file, queue, and table storage",
    "use_cases": ["File uploads", "Static assets", "Backups"]
  },
  ...
]
```

### `analyze_codebase`

Analyze a codebase to detect infrastructure needs.

```
Arguments:
  path: string (required) - Path to the codebase
  include_patterns: string[] (optional) - File patterns to include
  exclude_patterns: string[] (optional) - File patterns to exclude
```

Example response:
```json
{
  "analyzed_path": "/path/to/project",
  "files_scanned": 45,
  "detected_resources": [
    {
      "module": "postgresql",
      "confidence": 0.8,
      "reasons": ["package.json: matched prisma", "src/db.ts: matched DATABASE_URL"],
      "suggested_config": { "version": "14", "sku": "B_Standard_B1ms" }
    }
  ]
}
```

### `generate_infrastructure_yaml`

Generate a complete infrastructure.yaml configuration.

```
Arguments:
  project_name: string (required)
  environment: string (optional, default: "dev")
  business_unit: string (required)
  cost_center: string (required)
  owner_email: string (required)
  location: string (optional, default: "centralus")
  resources: array (required) - List of resources to include
```

Example:
```javascript
{
  "project_name": "myapp",
  "business_unit": "engineering",
  "cost_center": "CC-ENG-001",
  "owner_email": "team@example.com",
  "resources": [
    { "type": "postgresql", "name": "db" },
    { "type": "storage_account", "name": "data", "config": { "replication": "GRS" } }
  ]
}
```

### `validate_infrastructure_yaml`

Validate an infrastructure configuration.

```
Arguments:
  yaml_content: string - YAML content to validate
  file_path: string - Or path to YAML file
```

Example response:
```json
{
  "valid": true,
  "errors": [],
  "warnings": ["project_name is long; Azure resource names have length limits"],
  "summary": "Valid with warnings"
}
```

### `get_module_details`

Get detailed information about a specific module.

```
Arguments:
  module_name: string (required) - e.g., "storage_account", "postgresql"
```

## Example Workflow

1. **Analyze your codebase**:
   ```
   User: "What infrastructure does my project need?"
   Claude: [calls analyze_codebase with path to project]
   ```

2. **Review recommendations**:
   ```
   Claude: "Based on your Next.js app with Prisma, I recommend:
   - postgresql for your database
   - storage_account for file uploads
   - static_web_app for hosting
   - keyvault for secrets"
   ```

3. **Generate configuration**:
   ```
   User: "Generate the infrastructure.yaml"
   Claude: [calls generate_infrastructure_yaml]
   ```

4. **Validate and export**:
   ```
   User: "Validate this configuration"
   Claude: [calls validate_infrastructure_yaml]
   Claude: "Configuration is valid! Add this to your repo root as infrastructure.yaml"
   ```

## Supported Modules

| Module | Description |
|--------|-------------|
| `storage_account` | Azure Storage Account for blobs, files, queues |
| `postgresql` | Azure Database for PostgreSQL Flexible Server |
| `mongodb` | Azure Cosmos DB with MongoDB API |
| `keyvault` | Azure Key Vault for secrets and keys |
| `static_web_app` | Azure Static Web App for SPAs |

## Detection Patterns

The analyzer looks for:

- **Database connections**: Connection strings, ORM libraries (Prisma, TypeORM, Mongoose)
- **Storage usage**: S3/Blob SDK imports, file upload libraries
- **Frameworks**: React, Vue, Angular, Next.js, etc.
- **Environment variables**: DATABASE_URL, STORAGE_*, API keys
- **Package dependencies**: package.json, requirements.txt, go.mod

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Run locally (for testing)
npm start
```

## License

Internal use - Infrastructure Self-Service Platform
