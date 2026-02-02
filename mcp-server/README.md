# Infrastructure MCP App

An MCP App (Model Context Protocol Application) that provides an **interactive UI for infrastructure pattern generation**, rendering directly within Claude conversations. Built with the MCP SDK and `@modelcontextprotocol/ext-apps`.

## What is an MCP App?

MCP Apps extend the Model Context Protocol by adding interactive UI capabilities that render directly in the Claude conversation. Unlike traditional MCP servers that only provide text-based tools, MCP Apps can display rich forms, visualizations, and interactive elements.

This app provides:
- **Interactive pattern selection** with live configuration forms
- **T-shirt sizing** (small/medium/large) based on environment
- **Real-time YAML generation** and validation
- **Cost estimation** for infrastructure patterns
- **Pattern recommendations** based on codebase analysis

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Claude Desktop                     │
│  ┌────────────────────────────────────────────────┐ │
│  │  Interactive UI (rendered in conversation)     │ │
│  │  - Pattern selection dropdown                  │ │
│  │  - Configuration form with validation          │ │
│  │  - Generate button                             │ │
│  └────────────────────────────────────────────────┘ │
│                        ▲                             │
│                        │ App.sendMessage()           │
│                        │ App.callServerTool()        │
│                        ▼                             │
│  ┌────────────────────────────────────────────────┐ │
│  │          MCP App Server (HTTP/stdio)           │ │
│  │  - registerAppTool (generate_pattern_request)  │ │
│  │  - registerAppResource (UI HTML)               │ │
│  │  - Standard tools (list_patterns, etc.)        │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## Available Tools

### UI-Enabled Tool

#### `generate_pattern_request` (Interactive)

Opens an interactive UI form in Claude for configuring and generating infrastructure pattern requests.

**UI Features:**
- Pattern dropdown with descriptions
- Project name, environment, location inputs
- Business unit and owners (comma-separated emails)
- Dynamic configuration fields based on selected pattern
- Real-time YAML preview

### Standard Tools

#### `list_patterns`

List all available infrastructure patterns with optional category filtering.

Arguments:
- `verbose` (boolean, optional): Include full pattern details
- `category` (string, optional): Filter by "single" or "composite"

#### `analyze_files`

Analyze file contents to detect infrastructure patterns. Pass file contents from your codebase to get pattern recommendations.

Arguments:
- `files` (array, required): Array of `{path, content}` objects
- `project_name` (string, optional): Project name for context

**Recommended files:**
- `package.json` or `requirements.txt`
- `host.json` (Azure Functions)
- `staticwebapp.config.json` (Static Web Apps)
- Source files with database/storage imports

#### `validate_pattern_request`

Validate a pattern request YAML configuration.

Arguments:
- `yaml_content` (string, required): The YAML content to validate

#### `get_pattern_details`

Get detailed information about a specific pattern including config options, sizing, components, and cost estimates.

Arguments:
- `pattern_name` (string, required): Name of the pattern (e.g., "keyvault", "postgresql")

#### `estimate_cost`

Estimate monthly cost for a pattern deployment.

Arguments:
- `pattern` (string, required): Pattern name
- `environment` (string, optional): "dev", "staging", or "prod"
- `size` (string, optional): "small", "medium", or "large"

#### `generate_workflow`

Generate a GitHub Actions workflow file for GitOps-based provisioning.

Arguments:
- `infra_repo` (string, optional): Infrastructure automation repo name
- `github_org` (string, optional): GitHub organization

## Supported Patterns

### Single-Resource Patterns

| Pattern | Description | Components |
|---------|-------------|------------|
| `keyvault` | Key Vault with RBAC and access reviews | Key Vault, Security Groups, RBAC, Access Review |
| `postgresql` | PostgreSQL Flexible Server | PostgreSQL, Key Vault, Security Groups, RBAC |
| `mongodb` | Cosmos DB with MongoDB API | Cosmos DB, Security Groups, RBAC |
| `storage` | Storage Account with containers | Storage Account, Security Groups, RBAC |
| `function-app` | Azure Functions with dependencies | Function App, Storage, Key Vault, Security Groups |
| `sql-database` | Azure SQL Database | SQL Database, Security Groups, RBAC |
| `eventhub` | Event Hubs namespace | Event Hub, Security Groups, RBAC |
| `aks-namespace` | Kubernetes namespace in shared AKS | Namespace, Security Groups, RBAC |
| `linux-vm` | Linux Virtual Machine | VM, Managed Disks, Security Groups |
| `static-site` | Static Web App for SPAs | Static Web App, Security Groups |

### Composite Patterns

| Pattern | Description | Includes |
|---------|-------------|----------|
| `microservice` | Complete microservice stack | AKS Namespace + Event Hub + Storage |
| `web-app` | Full-stack web application | Static Site + Function App + PostgreSQL |
| `api-backend` | API backend with database | Function App + SQL Database + Key Vault |
| `data-pipeline` | Event-driven data pipeline | Event Hub + Function App + Storage + MongoDB |

## Pattern Configuration

### T-Shirt Sizing

Patterns use t-shirt sizing (small/medium/large) that resolves to environment-specific configurations:

| Size | Dev | Staging | Prod |
|------|-----|---------|------|
| small | Minimal resources | Basic resources | Production-ready |
| medium | Basic resources | Production-ready | High performance |
| large | Production-ready | High performance | Enterprise scale |

**Default sizes by environment:**
- dev → small
- staging → medium
- prod → medium

### Conditional Features

Features automatically enabled based on environment:
- **Diagnostics**: staging, prod
- **Access Reviews**: prod only
- **High Availability**: prod only
- **Geo-Redundant Backup**: prod only

## Local Development

### Running in HTTP Mode (for remote Claude connection)

```bash
cd mcp-server
npm install
npm run build
npm run start

# Server starts on http://0.0.0.0:3001
# MCP endpoint: http://0.0.0.0:3001/mcp
# Health check: http://0.0.0.0:3001/health
```

Expose via cloudflared tunnel:
```bash
npx cloudflared tunnel --url http://localhost:3001
```

Add to Claude settings as a custom connector with the cloudflared URL.

### Running in stdio Mode (for local Claude Code)

```bash
npm run start:stdio
```

Configure in Claude Code's `.mcp.json`:
```json
{
  "mcpServers": {
    "infrastructure": {
      "command": "node",
      "args": ["C:\\path\\to\\mcp-server\\dist\\server.js"],
      "env": {
        "MCP_TRANSPORT": "stdio"
      }
    }
  }
}
```

### Development Scripts

```bash
npm run build          # TypeScript compile + UI build + copy patterns.json
npm run build:ui       # Vite build (bundles UI to single HTML file)
npm run build:copy     # Copy patterns.generated.json to dist/
npm run dev            # Build and start in HTTP mode
npm run dev:stdio      # Build and start in stdio mode
```

## Project Structure

```
mcp-server/
├── src/
│   ├── server.ts                    # Main MCP app server
│   └── patterns.generated.json      # Auto-generated pattern definitions
├── ui/
│   ├── pattern-generator.html       # UI entry point
│   └── src/
│       └── pattern-generator.ts     # UI logic (App class)
├── dist/                            # Build output
│   ├── server.js                    # Compiled server
│   ├── patterns.generated.json      # Copied pattern data
│   └── ui/ui/pattern-generator.html # Bundled UI (single file)
├── package.json
├── tsconfig.json
├── vite.config.ts                   # Vite config (singlefile plugin)
└── README.md
```

## Pattern Management (Single Source of Truth)

Pattern definitions live in `config/patterns/*.yaml` (repository root). The MCP server loads auto-generated `patterns.generated.json` created by:

```bash
# From repository root
python3 scripts/generate-schema.py
```

This generates:
- `schemas/infrastructure.yaml.json` - JSON Schema for IDE validation
- `web/index.html` - Portal PATTERNS_DATA
- `templates/infrastructure-workflow.yaml` - Workflow valid_patterns list
- `mcp-server/src/patterns.generated.json` - MCP pattern data

**Never edit `patterns.generated.json` manually.** Always update `config/patterns/*.yaml` and regenerate.

## UI Implementation Details

The UI uses the `@modelcontextprotocol/ext-apps` SDK:

**Server-side** (`src/server.ts`):
```typescript
import { registerAppTool, registerAppResource, RESOURCE_MIME_TYPE } from "@modelcontextprotocol/ext-apps/server";

// Register UI-enabled tool
registerAppTool(
  server,
  "generate_pattern_request",
  {
    title: "Generate Infrastructure Pattern",
    description: "Interactive form...",
    inputSchema: {...},
    _meta: { ui: { resourceUri: "ui://pattern-generator/pattern-generator.html" } }
  },
  async (args) => {
    // Tool handler
  }
);

// Register UI resource
registerAppResource(
  server,
  "ui://pattern-generator/pattern-generator.html",
  "ui://pattern-generator/pattern-generator.html",
  { mimeType: RESOURCE_MIME_TYPE },
  async () => {
    const html = await fs.readFile(path.join(__dirname, "ui", "ui", "pattern-generator.html"), "utf-8");
    return { contents: [{ uri: "...", mimeType: RESOURCE_MIME_TYPE, text: html }] };
  }
);
```

**Client-side** (`ui/src/pattern-generator.ts`):
```typescript
import { App } from "@modelcontextprotocol/ext-apps";

const app = new App({ name: "Infrastructure Pattern Generator", version: "1.0.0" });

await app.connect();

// Call server tool
const result = await app.callServerTool({
  name: "generate_pattern_request",
  arguments: { pattern, project_name, ... }
});

// Send message back to Claude
await app.sendMessage({
  role: "user",
  content: { type: "text", text: `Generated YAML:\n\n\`\`\`yaml\n${yaml}\n\`\`\`` }
});
```

## Build Process

1. **TypeScript Compilation**: `tsc` compiles `src/server.ts` to `dist/server.js`
2. **UI Build**: `vite build` bundles `ui/pattern-generator.html` and `ui/src/pattern-generator.ts` into a single HTML file at `dist/ui/ui/pattern-generator.html` using `vite-plugin-singlefile`
3. **Pattern Copy**: Copies `src/patterns.generated.json` to `dist/patterns.generated.json`

The single-file UI bundle includes all JavaScript and CSS inline, making it easy to serve via the MCP resource API.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_TRANSPORT` | `http` | Transport mode: "http" or "stdio" |
| `PORT` | `3001` | HTTP port (http mode only) |

## API Endpoints (HTTP Mode)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (returns `{status, mode, version}`) |
| `/mcp` | POST | MCP protocol endpoint (StreamableHTTPServerTransport) |

## Troubleshooting

### Build fails with "Failed to resolve /src/pattern-generator.ts"

Check that `ui/pattern-generator.html` uses a relative path:
```html
<script type="module" src="./src/pattern-generator.ts"></script>
```

### Runtime error: "patternsData.patterns.reduce is not a function"

The `patterns.generated.json` has patterns as an object (not array). Ensure server code uses:
```typescript
const PATTERN_DEFINITIONS = patternsData.patterns; // Not .reduce()
```

### UI doesn't render in Claude

1. Verify the tool has `_meta: { ui: { resourceUri: "ui://..." } }`
2. Check that `registerAppResource` is called with the same URI
3. Ensure the HTML file exists at `dist/ui/ui/pattern-generator.html`
4. Test with `curl http://localhost:3001/health` to verify server is running

### Port 3001 already in use

Kill existing process:
```bash
# Windows
taskkill /F /IM node.exe

# Linux/Mac
pkill -f "node dist/server.js"
```

## Cost Estimates

Pattern costs vary by size and environment. Use the `estimate_cost` tool for accurate estimates based on Azure pricing.

**Example monthly costs (USD):**
- Key Vault (small/dev): ~$10
- PostgreSQL (medium/prod): ~$200
- Function App (small/dev): ~$30
- Composite patterns: Sum of component costs

## Security Notes

- Pattern requests include owner emails for RBAC delegation
- Security groups created per pattern with automatic owner assignment
- Access reviews enabled for prod environments
- Secrets stored in Key Vault, not in YAML files
- No authentication required for local/stdio mode
- HTTP mode intended for local development or tunneled connections

## Related Documentation

- **Platform Guide**: `infrastructure-platform-guide.md` (repository root)
- **Pattern Definitions**: `config/patterns/*.yaml`
- **MCP Apps**: https://modelcontextprotocol.io/docs/extensions/apps
- **MCP SDK**: https://github.com/modelcontextprotocol/typescript-sdk
