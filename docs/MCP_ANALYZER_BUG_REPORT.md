# MCP Infrastructure Server - analyze_codebase Bug Report

## Issue Summary

The `analyze_codebase` tool returns `files_scanned: 0` and fails to detect any infrastructure patterns, even when the codebase contains clear indicators for Azure Functions and Azure SQL.

## Environment

- **MCP Server URL**: `https://ca-mcp-prod.mangoflower-3bcf53fc.centralus.azurecontainerapps.io`
- **Test Codebase**: CorpoCache (personal finance dashboard)
- **Codebase Path**: `/home/zerocool/github/CorpoCache`

## Steps to Reproduce

### Test 1: Default patterns
```json
{
  "path": "/home/zerocool/github/CorpoCache"
}
```

**Result:**
```json
{
  "analyzed_path": "/home/zerocool/github/CorpoCache",
  "files_scanned": 0,
  "detected_resources": [],
  "summary": "No specific infrastructure patterns detected"
}
```

### Test 2: Explicit include patterns
```json
{
  "path": "/home/zerocool/github/CorpoCache",
  "include_patterns": ["**/package.json", "**/host.json", "**/*.ts", "**/*.js"],
  "exclude_patterns": ["**/node_modules/**", "**/dist/**"]
}
```

**Result:**
```json
{
  "analyzed_path": "/home/zerocool/github/CorpoCache",
  "files_scanned": 0,
  "detected_resources": [],
  "summary": "No specific infrastructure patterns detected"
}
```

## Expected Behavior

The analyzer should:
1. Scan files matching the include patterns
2. Report `files_scanned` > 0
3. Detect `function_app` requirement (Azure Functions indicators present)
4. Detect `azure_sql` requirement (mssql dependency present)

## Codebase Structure

```
CorpoCache/
├── api/
│   ├── package.json          # Contains @azure/functions, mssql
│   ├── host.json             # Azure Functions host config
│   ├── tsconfig.json
│   └── src/
│       ├── functions/        # 9 Azure Function handlers
│       │   ├── bills.ts
│       │   ├── creditCards.ts
│       │   ├── loans.ts
│       │   └── ...
│       ├── services/
│       │   └── database.ts   # mssql connection pooling
│       └── middleware/
│           └── auth.ts
├── sql/
│   └── 001_create_tables.sql # Database schema
├── js/                       # Frontend JavaScript
├── css/                      # Stylesheets
├── index.html
└── staticwebapp.config.json  # Azure Static Web Apps config
```

## Infrastructure Indicators Present

### 1. Azure Functions (should detect `function_app`)

**File: `api/package.json`**
```json
{
  "name": "corpocache-api",
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "mssql": "^10.0.0"
  },
  "devDependencies": {
    "azure-functions-core-tools": "^4.6.0"
  },
  "scripts": {
    "start": "func start"
  }
}
```

**File: `api/host.json`**
```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  },
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
```

**File: `api/src/functions/bills.ts` (and 8 other function files)**
```typescript
import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from '@azure/functions';
```

### 2. Azure SQL (should detect `azure_sql`)

**File: `api/package.json`**
```json
{
  "dependencies": {
    "mssql": "^10.0.0"
  }
}
```

**File: `api/src/services/database.ts`**
```typescript
import sql from 'mssql';

const config: sql.config = {
  server: process.env.SQL_SERVER || 'localhost',
  database: process.env.SQL_DATABASE || 'corpocache',
  // ...
};
```

**File: `sql/001_create_tables.sql`**
- 201 lines of T-SQL schema definition
- Creates 11 tables with foreign key relationships

### 3. Azure Static Web Apps (should detect `static_web_app`)

**File: `staticwebapp.config.json`**
```json
{
  "routes": [...],
  "navigationFallback": {
    "rewrite": "/index.html"
  },
  "platform": {
    "apiRuntime": "node:18"
  }
}
```

## Suggested Detection Rules

### Package.json Dependency Patterns

| Dependency | Detected Resource | Suggested Config |
|------------|-------------------|------------------|
| `@azure/functions` | `function_app` | `runtime: node` |
| `mssql` | `azure_sql` | - |
| `pg` or `postgres` | `postgresql` | - |
| `mongodb` or `mongoose` | `mongodb` | - |
| `@azure/storage-blob` | `storage_account` | - |
| `@azure/keyvault-secrets` | `keyvault` | - |
| `@azure/event-hubs` | `eventhub` | - |

### File Existence Patterns

| File Pattern | Detected Resource |
|--------------|-------------------|
| `host.json` with `ExtensionBundle` | `function_app` |
| `staticwebapp.config.json` | `static_web_app` |
| `*.sql` files in `sql/` or `migrations/` | Database resource |
| `Dockerfile` | Container-based deployment |
| `requirements.txt` with `azure-functions` | `function_app` (Python) |

### Code Import Patterns

| Import Pattern | Detected Resource |
|----------------|-------------------|
| `from '@azure/functions'` | `function_app` |
| `import sql from 'mssql'` | `azure_sql` |
| `from 'pg'` or `from 'postgres'` | `postgresql` |
| `from 'mongodb'` | `mongodb` |

## Potential Root Causes

### 1. File Globbing Issue
The glob library may not be resolving patterns correctly. Test with:
```javascript
const glob = require('glob');
const files = glob.sync('**/*.json', { cwd: '/path/to/codebase' });
console.log(files); // Should list files
```

### 2. Path Resolution
The path may not be accessible from the MCP server container:
- Is the path mounted/accessible?
- Are there permission issues?
- Is the path being URL-encoded incorrectly?

### 3. Missing Pattern Matchers
The analyzer may not have detection rules implemented. Verify:
```javascript
// Check if pattern matchers exist
const patterns = {
  'package.json': (content) => {
    const pkg = JSON.parse(content);
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };
    if (deps['@azure/functions']) return { type: 'function_app' };
    if (deps['mssql']) return { type: 'azure_sql' };
  }
};
```

### 4. Async/Await Issue
File reading may be failing silently:
```javascript
try {
  const content = await fs.readFile(filePath, 'utf-8');
} catch (err) {
  console.error(`Failed to read ${filePath}:`, err);
  // Is this error being swallowed?
}
```

## Suggested Debugging Steps

1. **Add verbose logging** to the file scanning loop
2. **Log the resolved glob patterns** before scanning
3. **Test glob patterns** independently with a simple script
4. **Verify file access** from the MCP server container
5. **Return partial results** even if some files fail to parse
6. **Add error collection** in the response for debugging

## Expected Response for This Codebase

```json
{
  "analyzed_path": "/home/zerocool/github/CorpoCache",
  "files_scanned": 15,
  "detected_resources": [
    {
      "type": "function_app",
      "confidence": "high",
      "evidence": [
        "api/package.json: @azure/functions dependency",
        "api/host.json: Azure Functions extension bundle",
        "api/src/functions/*.ts: 9 function handlers"
      ],
      "suggested_config": {
        "runtime": "node",
        "runtime_version": "18",
        "sku": "Y1"
      }
    },
    {
      "type": "azure_sql",
      "confidence": "high",
      "evidence": [
        "api/package.json: mssql dependency",
        "api/src/services/database.ts: SQL connection config",
        "sql/001_create_tables.sql: T-SQL schema"
      ],
      "suggested_config": {
        "sku": "Free",
        "databases": ["corpocache"]
      }
    },
    {
      "type": "static_web_app",
      "confidence": "medium",
      "evidence": [
        "staticwebapp.config.json: SWA configuration"
      ],
      "suggested_config": {
        "sku_tier": "Free"
      }
    }
  ],
  "summary": "Detected Azure Functions API with SQL database backend"
}
```

## Contact

If you need access to the test codebase or additional information, please reach out.
