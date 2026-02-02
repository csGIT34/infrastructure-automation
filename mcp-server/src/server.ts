#!/usr/bin/env node

/**
 * Infrastructure MCP App Server
 *
 * An MCP server that provides infrastructure pattern generation tools,
 * including an interactive UI that renders in Claude.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  registerAppTool,
  registerAppResource,
  RESOURCE_MIME_TYPE,
} from "@modelcontextprotocol/ext-apps/server";
import * as fs from "fs/promises";
import * as path from "path";
import { fileURLToPath } from "url";
import YAML from "yaml";
import express from "express";
import cors from "cors";
import { z } from "zod";

// Get __dirname equivalent in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load pattern definitions
const patternsData = JSON.parse(
  await fs.readFile(
    path.join(__dirname, "patterns.generated.json"),
    "utf-8"
  )
);

const PATTERN_DEFINITIONS = patternsData.patterns;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

async function listPatterns(verbose?: boolean, category?: string): Promise<string> {
  let patterns = Object.values(PATTERN_DEFINITIONS) as any[];

  if (category) {
    patterns = patterns.filter((p: any) => p.category === category);
  }

  if (verbose) {
    return JSON.stringify({ patterns }, null, 2);
  }

  return JSON.stringify({
    patterns: patterns.map((p: any) => ({
      name: p.name,
      description: p.description,
      category: p.category
    }))
  }, null, 2);
}

function analyzeFiles(args: { files: Array<{ path: string; content: string }>; project_name?: string }): string {
  const { files, project_name } = args;
  const results: any[] = [];

  // Pattern detection logic (simplified)
  files.forEach(file => {
    const content = file.content.toLowerCase();
    const path = file.path.toLowerCase();

    // Detect patterns based on file content
    if (content.includes("azure.storage") || content.includes("@azure/storage")) {
      results.push({ pattern: "storage", confidence: 0.8 });
    }
    if (content.includes("pg") || content.includes("postgresql") || content.includes("@azure/postgresql")) {
      results.push({ pattern: "postgresql", confidence: 0.8 });
    }
    if (content.includes("@azure/functions") || path.includes("host.json")) {
      results.push({ pattern: "function-app", confidence: 0.9 });
    }
    if (content.includes("@azure/keyvault") || content.includes("secretclient")) {
      results.push({ pattern: "keyvault", confidence: 0.8 });
    }
    if (path.includes("staticwebapp.config.json") || content.includes("staticwebapp")) {
      results.push({ pattern: "static-site", confidence: 0.9 });
    }
  });

  // Deduplicate and sort by confidence
  const uniqueResults = Array.from(new Map(results.map(r => [r.pattern, r])).values());
  uniqueResults.sort((a, b) => b.confidence - a.confidence);

  return JSON.stringify({
    project_name: project_name || "unknown",
    files_analyzed: files.length,
    detected_patterns: uniqueResults.slice(0, 5),
    summary: uniqueResults.length > 0
      ? `Detected ${uniqueResults.length} potential patterns. Top recommendation: ${uniqueResults[0].pattern}`
      : "No specific infrastructure patterns detected"
  }, null, 2);
}

function generatePatternRequest(args: any): string {
  const {
    pattern,
    project_name,
    environment = "dev",
    business_unit,
    owners,
    location = "eastus",
    config,
    action = "create"
  } = args;

  const yaml = {
    version: "1",
    action,
    metadata: {
      project: project_name,
      environment,
      business_unit,
      owners,
      location
    },
    pattern,
    pattern_version: "1.0.0",
    config
  };

  return YAML.stringify(yaml);
}

function validatePatternRequest(yamlContent: string): string {
  try {
    const doc = YAML.parse(yamlContent);

    if (!doc.pattern || !PATTERN_DEFINITIONS[doc.pattern]) {
      return JSON.stringify({
        valid: false,
        errors: [`Unknown pattern: ${doc.pattern}`]
      }, null, 2);
    }

    return JSON.stringify({
      valid: true,
      pattern: doc.pattern,
      environment: doc.metadata?.environment || "dev"
    }, null, 2);

  } catch (error: any) {
    return JSON.stringify({
      valid: false,
      errors: [`YAML parse error: ${error.message}`]
    }, null, 2);
  }
}

function getPatternDetails(patternName: string): string {
  const pattern = PATTERN_DEFINITIONS[patternName];

  if (!pattern) {
    return JSON.stringify({
      error: `Pattern '${patternName}' not found`,
      available_patterns: Object.keys(PATTERN_DEFINITIONS)
    }, null, 2);
  }

  return JSON.stringify(pattern, null, 2);
}

function estimateCost(args: { pattern: string; environment?: string; size?: string }): string {
  const { pattern, environment = "dev", size } = args;
  const patternDef = PATTERN_DEFINITIONS[pattern];

  if (!patternDef || !patternDef.estimated_costs) {
    return JSON.stringify({
      error: "Cost data not available for this pattern"
    }, null, 2);
  }

  const sizeKey = size || (environment === "prod" ? "medium" : environment === "staging" ? "medium" : "small");
  const cost = patternDef.estimated_costs[sizeKey]?.[environment] || 0;

  return JSON.stringify({
    pattern,
    environment,
    size: sizeKey,
    cost,
    currency: "USD",
    period: "monthly"
  }, null, 2);
}

function generateWorkflow(args: { infra_repo: string; github_org: string }): string {
  const { infra_repo = "infrastructure-automation", github_org = "csGIT34" } = args;

  return `# This is a simplified workflow template
name: Infrastructure GitOps

on:
  push:
    branches: [main]
    paths: ['infrastructure.yaml']

jobs:
  provision:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Trigger provisioning
        run: |
          gh api repos/${github_org}/${infra_repo}/dispatches \\
            --method POST \\
            --field event_type=provision \\
            --field client_payload[repository]=\$\{{ github.repository }} \\
            --field client_payload[commit_sha]=\$\{{ github.sha }}
        env:
          GH_TOKEN: \$\{{ secrets.INFRA_TOKEN }}
`;
}

// ============================================================================
// MCP SERVER SETUP
// ============================================================================

const server = new McpServer({
  name: "infrastructure-mcp-app",
  version: "2.0.0",
});

// Register standard tools
server.registerTool(
  "list_patterns",
  {
    description: "List all available infrastructure patterns",
    inputSchema: z.object({
      verbose: z.boolean().optional(),
      category: z.enum(["single", "composite"]).optional()
    })
  },
  async (args: any) => {
    const result = await listPatterns(args?.verbose, args?.category);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

server.registerTool(
  "analyze_files",
  {
    description: "Analyze file contents to detect infrastructure patterns",
    inputSchema: z.object({
      files: z.array(z.object({
        path: z.string(),
        content: z.string()
      })),
      project_name: z.string().optional()
    })
  },
  async (args: any) => {
    const result = analyzeFiles(args);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

server.registerTool(
  "validate_pattern_request",
  {
    description: "Validate a pattern request YAML configuration",
    inputSchema: z.object({
      yaml_content: z.string()
    })
  },
  async (args: any) => {
    const result = validatePatternRequest(args.yaml_content);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

server.registerTool(
  "get_pattern_details",
  {
    description: "Get detailed information about a specific pattern",
    inputSchema: z.object({
      pattern_name: z.string()
    })
  },
  async (args: any) => {
    const result = getPatternDetails(args.pattern_name);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

server.registerTool(
  "estimate_cost",
  {
    description: "Estimate monthly cost for a pattern",
    inputSchema: z.object({
      pattern: z.string(),
      environment: z.string().optional(),
      size: z.string().optional()
    })
  },
  async (args: any) => {
    const result = estimateCost(args);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

server.registerTool(
  "generate_workflow",
  {
    description: "Generate a GitHub Actions workflow file",
    inputSchema: z.object({
      infra_repo: z.string().optional(),
      github_org: z.string().optional()
    })
  },
  async (args: any) => {
    const result = generateWorkflow(args);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

// ============================================================================
// MCP APP: Register UI-enabled tool
// ============================================================================

const uiResourceUri = "ui://pattern-generator/pattern-generator.html";

registerAppTool(
  server,
  "generate_pattern_request",
  {
    title: "Generate Infrastructure Pattern",
    description: "Interactive form to generate infrastructure configuration YAML. Opens a UI in Claude for selecting patterns and configuring resources.",
    inputSchema: z.object({
      pattern: z.string(),
      project_name: z.string(),
      environment: z.string().optional(),
      business_unit: z.string(),
      owners: z.array(z.string()),
      location: z.string().optional(),
      config: z.record(z.any()).optional()
    }) as any,
    _meta: { ui: { resourceUri: uiResourceUri } }
  },
  async (args: any) => {
    const result = generatePatternRequest(args);
    return { content: [{ type: "text" as const, text: result }] };
  }
);

// Register the UI resource
registerAppResource(
  server,
  uiResourceUri,
  uiResourceUri,
  { mimeType: RESOURCE_MIME_TYPE },
  async () => {
    const htmlPath = path.join(__dirname, "ui", "ui", "pattern-generator.html");
    const html = await fs.readFile(htmlPath, "utf-8");
    return {
      contents: [
        { uri: uiResourceUri, mimeType: RESOURCE_MIME_TYPE, text: html }
      ]
    };
  }
);

// ============================================================================
// START SERVER
// ============================================================================

async function main() {
  const mode = process.env.MCP_TRANSPORT || "http";
  const port = parseInt(process.env.PORT || "3001", 10);

  if (mode === "stdio") {
    // Stdio transport for local development
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("Infrastructure MCP App running on stdio");

  } else {
    // HTTP transport for remote access (default)
    const app = express();
    app.use(cors());
    app.use(express.json());

    // Health check
    app.get("/health", (req, res) => {
      res.json({ status: "healthy", mode: "http", version: "2.0.0" });
    });

    // MCP endpoint
    app.post("/mcp", async (req, res) => {
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableJsonResponse: true,
      });
      res.on("close", () => transport.close());
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    });

    app.listen(port, () => {
      console.log(`Infrastructure MCP App v2.0 running on http://0.0.0.0:${port}`);
      console.log(`MCP endpoint: http://0.0.0.0:${port}/mcp`);
      console.log(`Health check: http://0.0.0.0:${port}/health`);
      console.log("");
      console.log("To use in Claude:");
      console.log(`  1. Expose via cloudflared: npx cloudflared tunnel --url http://localhost:${port}`);
      console.log(`  2. Add as custom connector in Claude settings`);
    });
  }
}

main().catch(console.error);
