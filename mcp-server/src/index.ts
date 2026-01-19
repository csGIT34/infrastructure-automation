#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "fs";
import * as path from "path";
import { glob } from "glob";
import YAML from "yaml";

// Module definitions with their config options
const MODULE_DEFINITIONS: Record<string, ModuleDefinition> = {
  function_app: {
    name: "function_app",
    description: "Azure Functions for serverless APIs and event processing",
    use_cases: [
      "REST APIs and webhooks",
      "Event-driven processing",
      "Scheduled jobs and automation",
      "Backend for SPAs and mobile apps"
    ],
    config_options: {
      runtime: { type: "string", default: "python", description: "Runtime (python, node, dotnet, java)" },
      runtime_version: { type: "string", default: "3.11", description: "Runtime version" },
      sku: { type: "string", default: "Y1", description: "SKU (Y1=free, B1=$13/mo, P1V2=$81/mo)" },
      os_type: { type: "string", default: "Linux", description: "OS type (Linux, Windows)" },
      app_settings: { type: "object", default: {}, description: "Environment variables" }
    },
    detection_patterns: [
      { pattern: /function|serverless|lambda|azure.*func/i, weight: 3 },
      { pattern: /fastapi|flask|express|api.*route/i, weight: 2 },
      { pattern: /FUNCTIONS_|AZURE_FUNCTIONS/i, weight: 5 },
      { pattern: /@azure\/functions|azure-functions/i, weight: 5 }
    ]
  },
  azure_sql: {
    name: "azure_sql",
    description: "Azure SQL Database - managed SQL Server",
    use_cases: [
      "Relational data with ACID transactions",
      "Complex queries and reporting",
      "Enterprise applications",
      "Migration from SQL Server"
    ],
    config_options: {
      sku: { type: "string", default: "Free", description: "SKU (Free, Basic=$5/mo, S0=$15/mo, S1=$30/mo)" },
      databases: {
        type: "array",
        default: [],
        description: "List of databases to create",
        items: {
          name: { type: "string", required: true },
          sku: { type: "string", default: "Free" },
          max_size_gb: { type: "number", default: 32 }
        }
      }
    },
    detection_patterns: [
      { pattern: /sql.?server|mssql|sqlserver|azure.*sql/i, weight: 5 },
      { pattern: /pyodbc|tedious|mssql-node/i, weight: 4 },
      { pattern: /SQL_SERVER|MSSQL_|AZURE_SQL/i, weight: 5 },
      { pattern: /\.query\(|executeQuery|ExecuteNonQuery/i, weight: 2 }
    ]
  },
  eventhub: {
    name: "eventhub",
    description: "Azure Event Hubs for event streaming and ingestion",
    use_cases: [
      "Real-time event streaming",
      "IoT data ingestion",
      "Log aggregation",
      "Event-driven architectures"
    ],
    config_options: {
      sku: { type: "string", default: "Basic", description: "SKU (Basic=$11/mo, Standard=$22/mo)" },
      capacity: { type: "number", default: 1, description: "Throughput units (1-20)" },
      partition_count: { type: "number", default: 2, description: "Partitions (2-32)" },
      message_retention: { type: "number", default: 1, description: "Retention days (1-7)" }
    },
    detection_patterns: [
      { pattern: /event.?hub|kafka|streaming|event.*driven/i, weight: 3 },
      { pattern: /@azure\/event-hubs|azure-eventhub/i, weight: 5 },
      { pattern: /EVENTHUB_|EVENT_HUB/i, weight: 5 },
      { pattern: /\.sendBatch|EventHubProducerClient/i, weight: 4 }
    ]
  },
  storage_account: {
    name: "storage_account",
    description: "Azure Storage Account for blob, file, queue, and table storage",
    use_cases: [
      "File uploads and downloads",
      "Static asset hosting",
      "Application data storage",
      "Backup storage",
      "Data lake storage"
    ],
    config_options: {
      tier: { type: "string", default: "Standard", description: "Account tier (Standard, Premium)" },
      replication: { type: "string", default: "LRS", description: "Replication type (LRS, GRS, ZRS, GZRS)" },
      versioning: { type: "boolean", default: false, description: "Enable blob versioning" },
      soft_delete_days: { type: "number", default: null, description: "Soft delete retention days" },
      containers: {
        type: "array",
        default: [],
        description: "List of containers to create",
        items: {
          name: { type: "string", required: true },
          access_type: { type: "string", default: "private", description: "private, blob, or container" }
        }
      }
    },
    detection_patterns: [
      { pattern: /S3|s3|blob|storage|upload|download|file.*storage/i, weight: 3 },
      { pattern: /multer|formidable|busboy/i, weight: 2 },
      { pattern: /AWS\.S3|@aws-sdk\/client-s3|azure.*storage|@azure\/storage-blob/i, weight: 5 },
      { pattern: /STORAGE_|BLOB_|S3_|AZURE_STORAGE/i, weight: 3 }
    ]
  },
  postgresql: {
    name: "postgresql",
    description: "Azure Database for PostgreSQL Flexible Server",
    use_cases: [
      "Relational database for applications",
      "ACID-compliant data storage",
      "Complex queries and joins",
      "Traditional web application backends"
    ],
    config_options: {
      version: { type: "string", default: "14", description: "PostgreSQL version (11, 12, 13, 14, 15)" },
      sku: { type: "string", default: "B_Standard_B1ms", description: "Server SKU" },
      storage_mb: { type: "number", default: 32768, description: "Storage size in MB" },
      backup_retention_days: { type: "number", default: 7, description: "Backup retention (7-35 days)" },
      geo_redundant_backup: { type: "boolean", default: false, description: "Enable geo-redundant backups" }
    },
    detection_patterns: [
      { pattern: /postgres|postgresql|pg_|psql/i, weight: 5 },
      { pattern: /prisma|typeorm|sequelize|knex/i, weight: 2 },
      { pattern: /DATABASE_URL.*postgres/i, weight: 5 },
      { pattern: /POSTGRES_|PG_HOST|PG_DATABASE/i, weight: 4 }
    ]
  },
  mongodb: {
    name: "mongodb",
    description: "Azure Cosmos DB with MongoDB API",
    use_cases: [
      "Document database for flexible schemas",
      "NoSQL data storage",
      "Real-time applications",
      "Content management systems"
    ],
    config_options: {
      serverless: { type: "boolean", default: false, description: "Use serverless tier" },
      consistency_level: { type: "string", default: "Session", description: "Consistency level" },
      throughput: { type: "number", default: 400, description: "Request units (if not serverless)" }
    },
    detection_patterns: [
      { pattern: /mongo|mongodb|mongoose/i, weight: 5 },
      { pattern: /MONGO_URI|MONGODB_|COSMOS_/i, weight: 4 },
      { pattern: /\.insertOne|\.findOne|\.aggregate/i, weight: 2 }
    ]
  },
  keyvault: {
    name: "keyvault",
    description: "Azure Key Vault for secrets, keys, and certificates",
    use_cases: [
      "Secure storage of API keys and secrets",
      "Certificate management",
      "Encryption key management",
      "Credential rotation"
    ],
    config_options: {
      sku: { type: "string", default: "standard", description: "SKU (standard, premium)" },
      soft_delete_days: { type: "number", default: 7, description: "Soft delete retention (7-90 days)" },
      purge_protection: { type: "boolean", default: false, description: "Enable purge protection" },
      rbac_enabled: { type: "boolean", default: true, description: "Use RBAC for access control" },
      default_action: { type: "string", default: "Allow", description: "Network default action" }
    },
    detection_patterns: [
      { pattern: /secret|api.?key|credential|password|token/i, weight: 2 },
      { pattern: /KEY_VAULT|KEYVAULT|AZURE_KEY/i, weight: 5 },
      { pattern: /\.env|dotenv|process\.env/i, weight: 1 }
    ]
  },
  static_web_app: {
    name: "static_web_app",
    description: "Azure Static Web App for hosting SPAs and static sites",
    use_cases: [
      "Single-page applications (React, Vue, Angular)",
      "Static websites",
      "JAMstack applications",
      "Frontend hosting with API integration"
    ],
    config_options: {
      sku_tier: { type: "string", default: "Free", description: "SKU tier (Free, Standard)" },
      sku_size: { type: "string", default: "Free", description: "SKU size (Free, Standard)" }
    },
    detection_patterns: [
      { pattern: /react|vue|angular|svelte|next|nuxt|gatsby/i, weight: 3 },
      { pattern: /package\.json.*"build"/i, weight: 2 },
      { pattern: /static|spa|frontend|web.?app/i, weight: 1 },
      { pattern: /index\.html|public\/|dist\//i, weight: 2 }
    ]
  }
};

interface ModuleDefinition {
  name: string;
  description: string;
  use_cases: string[];
  config_options: Record<string, ConfigOption>;
  detection_patterns: Array<{ pattern: RegExp; weight: number }>;
}

interface ConfigOption {
  type: string;
  default: any;
  description: string;
  required?: boolean;
  items?: Record<string, any>;
}

interface AnalysisResult {
  module: string;
  confidence: number;
  reasons: string[];
  suggested_config: Record<string, any>;
}

// Create the MCP server
const server = new Server(
  {
    name: "infrastructure-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Define available tools
const tools: Tool[] = [
  {
    name: "list_available_modules",
    description: "List all available Terraform modules with their configuration options. Use this to understand what infrastructure resources can be provisioned.",
    inputSchema: {
      type: "object",
      properties: {
        verbose: {
          type: "boolean",
          description: "Include detailed config options for each module",
          default: false
        }
      }
    }
  },
  {
    name: "analyze_codebase",
    description: "Analyze a codebase to detect what infrastructure resources it needs. Scans for database connections, storage usage, frameworks, and environment variables.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Path to the codebase to analyze"
        },
        include_patterns: {
          type: "array",
          items: { type: "string" },
          description: "File patterns to include (e.g., ['**/*.ts', '**/*.js'])",
          default: ["**/*.ts", "**/*.js", "**/*.tsx", "**/*.jsx", "**/*.py", "**/*.go", "**/*.cs", "**/*.java", "**/*.env*", "**/package.json", "**/requirements.txt", "**/go.mod"]
        },
        exclude_patterns: {
          type: "array",
          items: { type: "string" },
          description: "File patterns to exclude",
          default: ["**/node_modules/**", "**/dist/**", "**/build/**", "**/.git/**", "**/vendor/**"]
        }
      },
      required: ["path"]
    }
  },
  {
    name: "generate_infrastructure_yaml",
    description: "Generate an infrastructure.yaml file based on detected or specified resources. Creates a valid configuration for the GitOps workflow.",
    inputSchema: {
      type: "object",
      properties: {
        project_name: {
          type: "string",
          description: "Project name (used in resource naming)"
        },
        environment: {
          type: "string",
          description: "Environment (dev, staging, prod)",
          default: "dev"
        },
        business_unit: {
          type: "string",
          description: "Business unit for cost allocation"
        },
        cost_center: {
          type: "string",
          description: "Cost center code"
        },
        owner_email: {
          type: "string",
          description: "Owner email for notifications"
        },
        location: {
          type: "string",
          description: "Azure region",
          default: "centralus"
        },
        resources: {
          type: "array",
          description: "List of resources to include",
          items: {
            type: "object",
            properties: {
              type: { type: "string" },
              name: { type: "string" },
              config: { type: "object" }
            }
          }
        }
      },
      required: ["project_name", "business_unit", "cost_center", "owner_email", "resources"]
    }
  },
  {
    name: "validate_infrastructure_yaml",
    description: "Validate an infrastructure.yaml configuration against the schema and available modules.",
    inputSchema: {
      type: "object",
      properties: {
        yaml_content: {
          type: "string",
          description: "YAML content to validate"
        },
        file_path: {
          type: "string",
          description: "Path to YAML file to validate (alternative to yaml_content)"
        }
      }
    }
  },
  {
    name: "get_module_details",
    description: "Get detailed information about a specific Terraform module including all config options and example usage.",
    inputSchema: {
      type: "object",
      properties: {
        module_name: {
          type: "string",
          description: "Name of the module (e.g., 'storage_account', 'postgresql')"
        }
      },
      required: ["module_name"]
    }
  }
];

// Tool handlers
async function listAvailableModules(verbose: boolean = false): Promise<string> {
  const modules = Object.values(MODULE_DEFINITIONS);

  if (verbose) {
    return JSON.stringify(modules.map(m => ({
      name: m.name,
      description: m.description,
      use_cases: m.use_cases,
      config_options: Object.entries(m.config_options).map(([key, opt]) => ({
        name: key,
        type: opt.type,
        default: opt.default,
        description: opt.description
      }))
    })), null, 2);
  }

  return JSON.stringify(modules.map(m => ({
    name: m.name,
    description: m.description,
    use_cases: m.use_cases
  })), null, 2);
}

async function analyzeCodebase(
  targetPath: string,
  includePatterns: string[] = ["**/*.ts", "**/*.js", "**/*.tsx", "**/*.jsx", "**/*.py", "**/*.env*", "**/package.json"],
  excludePatterns: string[] = ["**/node_modules/**", "**/dist/**", "**/.git/**"]
): Promise<string> {
  const results: AnalysisResult[] = [];
  const detectedPatterns: Map<string, { matches: string[]; totalWeight: number }> = new Map();

  // Initialize detection tracking
  for (const moduleName of Object.keys(MODULE_DEFINITIONS)) {
    detectedPatterns.set(moduleName, { matches: [], totalWeight: 0 });
  }

  try {
    // Find files matching patterns
    const files = await glob(includePatterns, {
      cwd: targetPath,
      ignore: excludePatterns,
      absolute: true,
      nodir: true
    });

    // Analyze each file
    for (const file of files.slice(0, 100)) { // Limit to 100 files
      try {
        const content = fs.readFileSync(file, "utf-8");
        const relativePath = path.relative(targetPath, file);

        // Check each module's detection patterns
        for (const [moduleName, moduleDef] of Object.entries(MODULE_DEFINITIONS)) {
          for (const { pattern, weight } of moduleDef.detection_patterns) {
            if (pattern.test(content) || pattern.test(relativePath)) {
              const detection = detectedPatterns.get(moduleName)!;
              const matchDesc = `${relativePath}: matched ${pattern.source}`;
              if (!detection.matches.includes(matchDesc)) {
                detection.matches.push(matchDesc);
                detection.totalWeight += weight;
              }
            }
          }
        }
      } catch (e) {
        // Skip unreadable files
      }
    }

    // Build results
    for (const [moduleName, detection] of detectedPatterns) {
      if (detection.totalWeight > 0) {
        const confidence = Math.min(detection.totalWeight / 10, 1); // Normalize to 0-1
        const moduleDef = MODULE_DEFINITIONS[moduleName];

        // Generate suggested config based on detection
        const suggestedConfig: Record<string, any> = {};
        for (const [key, opt] of Object.entries(moduleDef.config_options)) {
          if (opt.default !== null) {
            suggestedConfig[key] = opt.default;
          }
        }

        results.push({
          module: moduleName,
          confidence,
          reasons: detection.matches.slice(0, 5), // Top 5 matches
          suggested_config: suggestedConfig
        });
      }
    }

    // Sort by confidence
    results.sort((a, b) => b.confidence - a.confidence);

    // Always recommend keyvault if other resources detected
    if (results.length > 0 && !results.find(r => r.module === "keyvault")) {
      results.push({
        module: "keyvault",
        confidence: 0.5,
        reasons: ["Recommended for secure secret management with other resources"],
        suggested_config: { sku: "standard", rbac_enabled: true }
      });
    }

    return JSON.stringify({
      analyzed_path: targetPath,
      files_scanned: files.length,
      detected_resources: results,
      summary: results.length > 0
        ? `Detected ${results.length} potential infrastructure needs`
        : "No specific infrastructure patterns detected"
    }, null, 2);

  } catch (error) {
    return JSON.stringify({
      error: `Failed to analyze codebase: ${error}`,
      analyzed_path: targetPath
    }, null, 2);
  }
}

function generateInfrastructureYaml(params: {
  project_name: string;
  environment?: string;
  business_unit: string;
  cost_center: string;
  owner_email: string;
  location?: string;
  resources: Array<{ type: string; name: string; config?: Record<string, any> }>;
}): string {
  const config = {
    metadata: {
      project_name: params.project_name,
      environment: params.environment || "dev",
      business_unit: params.business_unit,
      cost_center: params.cost_center,
      owner_email: params.owner_email,
      location: params.location || "centralus"
    },
    resources: params.resources.map(r => {
      const moduleDef = MODULE_DEFINITIONS[r.type];
      const resourceConfig: Record<string, any> = {
        type: r.type,
        name: r.name
      };

      // Build config with defaults and overrides
      if (moduleDef && (r.config || Object.keys(moduleDef.config_options).length > 0)) {
        const finalConfig: Record<string, any> = {};
        for (const [key, opt] of Object.entries(moduleDef.config_options)) {
          if (r.config && key in r.config) {
            finalConfig[key] = r.config[key];
          } else if (opt.default !== null && opt.default !== undefined) {
            // Only include non-null defaults for cleaner output
            if (opt.type !== "array" || (Array.isArray(opt.default) && opt.default.length > 0)) {
              finalConfig[key] = opt.default;
            }
          }
        }
        if (Object.keys(finalConfig).length > 0) {
          resourceConfig.config = finalConfig;
        }
      } else if (r.config) {
        resourceConfig.config = r.config;
      }

      return resourceConfig;
    })
  };

  const yamlContent = YAML.stringify(config, { indent: 2 });

  const header = `# Infrastructure Configuration
# Generated by Infrastructure MCP Server
# Documentation: https://github.com/csGIT34/infrastructure-automation

`;

  return header + yamlContent;
}

function validateInfrastructureYaml(yamlContent: string): string {
  const errors: string[] = [];
  const warnings: string[] = [];

  try {
    const config = YAML.parse(yamlContent);

    // Validate metadata
    if (!config.metadata) {
      errors.push("Missing 'metadata' section");
    } else {
      const requiredMeta = ["project_name", "environment", "business_unit", "cost_center", "owner_email"];
      for (const field of requiredMeta) {
        if (!config.metadata[field]) {
          errors.push(`Missing metadata.${field}`);
        }
      }

      if (config.metadata.environment && !["dev", "staging", "prod"].includes(config.metadata.environment)) {
        warnings.push(`Environment '${config.metadata.environment}' is not standard (dev, staging, prod)`);
      }

      if (config.metadata.project_name && config.metadata.project_name.length > 20) {
        warnings.push("project_name is long; Azure resource names have length limits");
      }
    }

    // Validate resources
    if (!config.resources) {
      errors.push("Missing 'resources' section");
    } else if (!Array.isArray(config.resources)) {
      errors.push("'resources' must be an array");
    } else if (config.resources.length === 0) {
      errors.push("'resources' array is empty");
    } else {
      const validTypes = Object.keys(MODULE_DEFINITIONS);

      for (let i = 0; i < config.resources.length; i++) {
        const resource = config.resources[i];

        if (!resource.type) {
          errors.push(`Resource ${i + 1}: missing 'type'`);
        } else if (!validTypes.includes(resource.type)) {
          errors.push(`Resource ${i + 1}: invalid type '${resource.type}'. Valid types: ${validTypes.join(", ")}`);
        }

        if (!resource.name) {
          errors.push(`Resource ${i + 1}: missing 'name'`);
        } else if (!/^[a-z0-9-]+$/.test(resource.name)) {
          warnings.push(`Resource ${i + 1}: name '${resource.name}' should be lowercase alphanumeric with hyphens`);
        }

        // Validate config options if module is known
        if (resource.type && resource.config && MODULE_DEFINITIONS[resource.type]) {
          const moduleDef = MODULE_DEFINITIONS[resource.type];
          for (const key of Object.keys(resource.config)) {
            if (!moduleDef.config_options[key]) {
              warnings.push(`Resource ${i + 1} (${resource.type}): unknown config option '${key}'`);
            }
          }
        }
      }
    }

    return JSON.stringify({
      valid: errors.length === 0,
      errors,
      warnings,
      summary: errors.length === 0
        ? (warnings.length > 0 ? "Valid with warnings" : "Valid")
        : `Invalid: ${errors.length} error(s)`
    }, null, 2);

  } catch (e) {
    return JSON.stringify({
      valid: false,
      errors: [`YAML parse error: ${e}`],
      warnings: [],
      summary: "Invalid YAML syntax"
    }, null, 2);
  }
}

function getModuleDetails(moduleName: string): string {
  const moduleDef = MODULE_DEFINITIONS[moduleName];

  if (!moduleDef) {
    return JSON.stringify({
      error: `Unknown module '${moduleName}'`,
      available_modules: Object.keys(MODULE_DEFINITIONS)
    }, null, 2);
  }

  // Generate example config
  const exampleConfig: Record<string, any> = {};
  for (const [key, opt] of Object.entries(moduleDef.config_options)) {
    exampleConfig[key] = opt.default;
  }

  const exampleYaml = `resources:
  - type: ${moduleName}
    name: my${moduleName.replace(/_/g, "")}
    config:
${Object.entries(exampleConfig)
  .filter(([_, v]) => v !== null && v !== undefined && !(Array.isArray(v) && v.length === 0))
  .map(([k, v]) => `      ${k}: ${typeof v === "string" ? v : JSON.stringify(v)}`)
  .join("\n")}`;

  return JSON.stringify({
    name: moduleDef.name,
    description: moduleDef.description,
    use_cases: moduleDef.use_cases,
    config_options: Object.entries(moduleDef.config_options).map(([key, opt]) => ({
      name: key,
      type: opt.type,
      default: opt.default,
      description: opt.description,
      required: opt.required || false
    })),
    example_yaml: exampleYaml
  }, null, 2);
}

// Register tool handlers
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    let result: string;

    switch (name) {
      case "list_available_modules":
        result = await listAvailableModules(args?.verbose as boolean);
        break;

      case "analyze_codebase":
        result = await analyzeCodebase(
          args?.path as string,
          args?.include_patterns as string[],
          args?.exclude_patterns as string[]
        );
        break;

      case "generate_infrastructure_yaml":
        result = generateInfrastructureYaml(args as any);
        break;

      case "validate_infrastructure_yaml":
        const yamlContent = args?.yaml_content as string ||
          (args?.file_path ? fs.readFileSync(args.file_path as string, "utf-8") : "");
        result = validateInfrastructureYaml(yamlContent);
        break;

      case "get_module_details":
        result = getModuleDetails(args?.module_name as string);
        break;

      default:
        throw new Error(`Unknown tool: ${name}`);
    }

    return {
      content: [{ type: "text", text: result }]
    };

  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error}` }],
      isError: true
    };
  }
});

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Infrastructure MCP Server running on stdio");
}

main().catch(console.error);
