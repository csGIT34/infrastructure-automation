#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "fs";
import * as path from "path";
import { glob } from "glob";
import YAML from "yaml";
import express from "express";
import cors from "cors";

// =============================================================================
// PATTERN DEFINITIONS - Single source of truth for infrastructure patterns
// =============================================================================

interface PatternDefinition {
  name: string;
  description: string;
  category: "single" | "composite";
  components: string[];
  use_cases: string[];
  config: {
    required: string[];
    optional: Record<string, ConfigOption>;
  };
  sizing: {
    small: SizingConfig;
    medium: SizingConfig;
    large: SizingConfig;
  };
  estimated_costs?: {
    small: EnvironmentCosts;
    medium: EnvironmentCosts;
    large: EnvironmentCosts;
  };
  detection_patterns: Array<{ pattern: RegExp; weight: number }>;
}

interface SizingConfig {
  dev: Record<string, any>;
  staging: Record<string, any>;
  prod: Record<string, any>;
}

interface EnvironmentCosts {
  dev: number;
  staging: number;
  prod: number;
}

interface ConfigOption {
  type: string;
  default: any;
  description: string;
  required?: boolean;
  items?: Record<string, any>;
}

// Pattern definitions - Developers interact ONLY through patterns
const PATTERN_DEFINITIONS: Record<string, PatternDefinition> = {
  keyvault: {
    name: "keyvault",
    description: "Azure Key Vault with security groups, RBAC, and optional access reviews. Includes automatic diagnostics in staging/prod.",
    category: "single",
    components: ["keyvault", "security-groups", "rbac-assignments", "access-review", "diagnostic-settings"],
    use_cases: [
      "Secure storage of API keys and secrets",
      "Certificate management",
      "Encryption key management",
      "Team secrets with access reviews"
    ],
    config: {
      required: ["name"],
      optional: {
        access_reviewers: { type: "array", default: [], description: "Email addresses for access review (required for prod)" },
        enable_private_endpoint: { type: "boolean", default: false, description: "Enable private endpoint access" },
        subnet_id: { type: "string", default: "", description: "Subnet ID for private endpoint (if enabled)" }
      }
    },
    sizing: {
      small: {
        dev: { sku: "standard", soft_delete_days: 7, purge_protection: false },
        staging: { sku: "standard", soft_delete_days: 30, purge_protection: false },
        prod: { sku: "premium", soft_delete_days: 90, purge_protection: true }
      },
      medium: {
        dev: { sku: "standard", soft_delete_days: 7, purge_protection: false },
        staging: { sku: "premium", soft_delete_days: 60, purge_protection: true },
        prod: { sku: "premium", soft_delete_days: 90, purge_protection: true }
      },
      large: {
        dev: { sku: "premium", soft_delete_days: 30, purge_protection: false },
        staging: { sku: "premium", soft_delete_days: 90, purge_protection: true },
        prod: { sku: "premium", soft_delete_days: 90, purge_protection: true }
      }
    },
    estimated_costs: {
      small: { dev: 5, staging: 15, prod: 30 },
      medium: { dev: 10, staging: 25, prod: 45 },
      large: { dev: 20, staging: 40, prod: 75 }
    },
    detection_patterns: [
      { pattern: /secret|api.?key|credential|password|token/i, weight: 2 },
      { pattern: /KEY_VAULT|KEYVAULT|AZURE_KEY/i, weight: 5 },
      { pattern: /\.env|dotenv|process\.env/i, weight: 1 }
    ]
  },

  postgresql: {
    name: "postgresql",
    description: "Azure Database for PostgreSQL Flexible Server with security groups, RBAC, and secrets stored in Key Vault.",
    category: "single",
    components: ["postgresql", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "Relational database for applications",
      "ACID-compliant data storage",
      "Complex queries and joins",
      "Traditional web application backends"
    ],
    config: {
      required: ["name"],
      optional: {
        version: { type: "string", default: "14", description: "PostgreSQL version (11, 12, 13, 14, 15, 16)" },
        high_availability: { type: "boolean", default: false, description: "Enable zone-redundant HA (auto in prod)" },
        databases: { type: "array", default: [], description: "List of database names to create" }
      }
    },
    sizing: {
      small: {
        dev: { sku: "B_Standard_B1ms", storage_mb: 32768 },
        staging: { sku: "B_Standard_B2s", storage_mb: 65536 },
        prod: { sku: "GP_Standard_D2s_v3", storage_mb: 131072 }
      },
      medium: {
        dev: { sku: "B_Standard_B2s", storage_mb: 65536 },
        staging: { sku: "GP_Standard_D2s_v3", storage_mb: 131072 },
        prod: { sku: "GP_Standard_D4s_v3", storage_mb: 262144 }
      },
      large: {
        dev: { sku: "GP_Standard_D2s_v3", storage_mb: 131072 },
        staging: { sku: "GP_Standard_D4s_v3", storage_mb: 262144 },
        prod: { sku: "GP_Standard_D8s_v3", storage_mb: 524288 }
      }
    },
    estimated_costs: {
      small: { dev: 15, staging: 45, prod: 150 },
      medium: { dev: 45, staging: 150, prod: 300 },
      large: { dev: 150, staging: 300, prod: 600 }
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
    description: "Azure Cosmos DB with MongoDB API, security groups, RBAC, and connection string in Key Vault.",
    category: "single",
    components: ["mongodb", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "Document database for flexible schemas",
      "NoSQL data storage",
      "Real-time applications",
      "Content management systems"
    ],
    config: {
      required: ["name"],
      optional: {
        serverless: { type: "boolean", default: false, description: "Use serverless tier (cost-effective for dev)" },
        consistency_level: { type: "string", default: "Session", description: "Consistency level (Strong, Session, etc.)" },
        collections: { type: "array", default: [], description: "Collections to create" }
      }
    },
    sizing: {
      small: {
        dev: { throughput: 400, serverless: true },
        staging: { throughput: 400, serverless: false },
        prod: { throughput: 1000, serverless: false }
      },
      medium: {
        dev: { throughput: 400, serverless: true },
        staging: { throughput: 1000, serverless: false },
        prod: { throughput: 2000, serverless: false }
      },
      large: {
        dev: { throughput: 1000, serverless: false },
        staging: { throughput: 2000, serverless: false },
        prod: { throughput: 4000, serverless: false }
      }
    },
    estimated_costs: {
      small: { dev: 25, staging: 50, prod: 150 },
      medium: { dev: 25, staging: 100, prod: 250 },
      large: { dev: 75, staging: 200, prod: 400 }
    },
    detection_patterns: [
      { pattern: /mongo|mongodb|mongoose/i, weight: 5 },
      { pattern: /MONGO_URI|MONGODB_|COSMOS_/i, weight: 4 },
      { pattern: /\.insertOne|\.findOne|\.aggregate/i, weight: 2 }
    ]
  },

  storage: {
    name: "storage",
    description: "Azure Storage Account with containers, security groups, and optional private endpoints.",
    category: "single",
    components: ["storage-account", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "File uploads and downloads",
      "Static asset hosting",
      "Application data storage",
      "Backup storage",
      "Data lake storage"
    ],
    config: {
      required: ["name"],
      optional: {
        containers: { type: "array", default: [], description: "Blob containers to create" },
        enable_versioning: { type: "boolean", default: false, description: "Enable blob versioning" },
        enable_static_website: { type: "boolean", default: false, description: "Enable static website hosting" }
      }
    },
    sizing: {
      small: {
        dev: { tier: "Standard", replication: "LRS" },
        staging: { tier: "Standard", replication: "LRS" },
        prod: { tier: "Standard", replication: "GRS" }
      },
      medium: {
        dev: { tier: "Standard", replication: "LRS" },
        staging: { tier: "Standard", replication: "ZRS" },
        prod: { tier: "Standard", replication: "GZRS" }
      },
      large: {
        dev: { tier: "Standard", replication: "ZRS" },
        staging: { tier: "Premium", replication: "ZRS" },
        prod: { tier: "Premium", replication: "GZRS" }
      }
    },
    estimated_costs: {
      small: { dev: 5, staging: 10, prod: 25 },
      medium: { dev: 10, staging: 25, prod: 50 },
      large: { dev: 25, staging: 75, prod: 150 }
    },
    detection_patterns: [
      { pattern: /S3|s3|blob|storage|upload|download|file.*storage/i, weight: 3 },
      { pattern: /multer|formidable|busboy/i, weight: 2 },
      { pattern: /AWS\.S3|@aws-sdk\/client-s3|azure.*storage|@azure\/storage-blob/i, weight: 5 },
      { pattern: /STORAGE_|BLOB_|S3_|AZURE_STORAGE/i, weight: 3 }
    ]
  },

  "function-app": {
    name: "function-app",
    description: "Azure Functions app with storage, security groups, and app settings in Key Vault.",
    category: "single",
    components: ["function-app", "storage-account", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "REST APIs and webhooks",
      "Event-driven processing",
      "Scheduled jobs and automation",
      "Backend for SPAs and mobile apps"
    ],
    config: {
      required: ["name"],
      optional: {
        runtime: { type: "string", default: "python", description: "Runtime (python, node, dotnet, java)" },
        runtime_version: { type: "string", default: "3.11", description: "Runtime version" },
        app_settings: { type: "object", default: {}, description: "Environment variables" },
        cors_origins: { type: "array", default: ["*"], description: "Allowed CORS origins" }
      }
    },
    sizing: {
      small: {
        dev: { sku: "Y1", os_type: "Linux" },
        staging: { sku: "Y1", os_type: "Linux" },
        prod: { sku: "P1v2", os_type: "Linux" }
      },
      medium: {
        dev: { sku: "Y1", os_type: "Linux" },
        staging: { sku: "P1v2", os_type: "Linux" },
        prod: { sku: "P2v2", os_type: "Linux" }
      },
      large: {
        dev: { sku: "B1", os_type: "Linux" },
        staging: { sku: "P2v2", os_type: "Linux" },
        prod: { sku: "P3v2", os_type: "Linux" }
      }
    },
    estimated_costs: {
      small: { dev: 0, staging: 0, prod: 81 },
      medium: { dev: 0, staging: 81, prod: 162 },
      large: { dev: 13, staging: 162, prod: 324 }
    },
    detection_patterns: [
      { pattern: /function|serverless|lambda|azure.*func/i, weight: 3 },
      { pattern: /fastapi|flask|express|api.*route/i, weight: 2 },
      { pattern: /FUNCTIONS_|AZURE_FUNCTIONS/i, weight: 5 },
      { pattern: /@azure\/functions|azure-functions/i, weight: 5 },
      { pattern: /host\.json/i, weight: 4 },
      { pattern: /extensionBundle/i, weight: 5 }
    ]
  },

  "sql-database": {
    name: "sql-database",
    description: "Azure SQL Database with security groups, firewall rules, and connection string in Key Vault.",
    category: "single",
    components: ["azure-sql", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "Relational data with ACID transactions",
      "Complex queries and reporting",
      "Enterprise applications",
      "Migration from SQL Server"
    ],
    config: {
      required: ["name"],
      optional: {
        admin_login: { type: "string", default: "sqladmin", description: "Administrator login name" },
        databases: { type: "array", default: [], description: "Databases to create" },
        firewall_rules: { type: "array", default: [], description: "IP firewall rules" }
      }
    },
    sizing: {
      small: {
        dev: { sku: "Basic", max_size_gb: 2 },
        staging: { sku: "S0", max_size_gb: 10 },
        prod: { sku: "S1", max_size_gb: 50 }
      },
      medium: {
        dev: { sku: "S0", max_size_gb: 10 },
        staging: { sku: "S1", max_size_gb: 50 },
        prod: { sku: "S2", max_size_gb: 100 }
      },
      large: {
        dev: { sku: "S1", max_size_gb: 50 },
        staging: { sku: "S2", max_size_gb: 100 },
        prod: { sku: "S3", max_size_gb: 250 }
      }
    },
    estimated_costs: {
      small: { dev: 5, staging: 15, prod: 30 },
      medium: { dev: 15, staging: 30, prod: 75 },
      large: { dev: 30, staging: 75, prod: 150 }
    },
    detection_patterns: [
      { pattern: /sql.?server|sqlserver|azure.*sql/i, weight: 5 },
      { pattern: /["']mssql["']/i, weight: 8 },
      { pattern: /pyodbc|tedious|mssql-node/i, weight: 6 },
      { pattern: /SQL_SERVER|MSSQL_|AZURE_SQL/i, weight: 5 }
    ]
  },

  eventhub: {
    name: "eventhub",
    description: "Azure Event Hubs namespace with hubs, consumer groups, and connection string in Key Vault.",
    category: "single",
    components: ["eventhub", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "Real-time event streaming",
      "IoT data ingestion",
      "Log aggregation",
      "Event-driven architectures"
    ],
    config: {
      required: ["name"],
      optional: {
        hubs: { type: "array", default: [], description: "Event hubs to create" },
        consumer_groups: { type: "array", default: [], description: "Consumer groups" },
        partition_count: { type: "number", default: 2, description: "Partitions per hub" }
      }
    },
    sizing: {
      small: {
        dev: { sku: "Basic", capacity: 1 },
        staging: { sku: "Basic", capacity: 1 },
        prod: { sku: "Standard", capacity: 2 }
      },
      medium: {
        dev: { sku: "Basic", capacity: 1 },
        staging: { sku: "Standard", capacity: 2 },
        prod: { sku: "Standard", capacity: 4 }
      },
      large: {
        dev: { sku: "Standard", capacity: 2 },
        staging: { sku: "Standard", capacity: 4 },
        prod: { sku: "Standard", capacity: 8 }
      }
    },
    estimated_costs: {
      small: { dev: 11, staging: 11, prod: 44 },
      medium: { dev: 11, staging: 44, prod: 88 },
      large: { dev: 44, staging: 88, prod: 176 }
    },
    detection_patterns: [
      { pattern: /event.?hub|kafka|streaming|event.*driven/i, weight: 3 },
      { pattern: /@azure\/event-hubs|azure-eventhub/i, weight: 5 },
      { pattern: /EVENTHUB_|EVENT_HUB/i, weight: 5 },
      { pattern: /\.sendBatch|EventHubProducerClient/i, weight: 4 }
    ]
  },

  "aks-namespace": {
    name: "aks-namespace",
    description: "Kubernetes namespace in shared AKS cluster with resource quotas, RBAC, and network policies.",
    category: "single",
    components: ["aks-namespace", "security-groups", "rbac-assignments"],
    use_cases: [
      "Kubernetes workloads",
      "Microservices deployment",
      "Container orchestration",
      "Team isolation in shared cluster"
    ],
    config: {
      required: ["name", "aks_cluster_name", "aks_resource_group"],
      optional: {
        pod_limit: { type: "number", default: 20, description: "Maximum pods in namespace" },
        enable_network_policy: { type: "boolean", default: true, description: "Enable network isolation" },
        labels: { type: "object", default: {}, description: "Namespace labels" }
      }
    },
    sizing: {
      small: {
        dev: { cpu_limit: "2", memory_limit: "4Gi" },
        staging: { cpu_limit: "4", memory_limit: "8Gi" },
        prod: { cpu_limit: "8", memory_limit: "16Gi" }
      },
      medium: {
        dev: { cpu_limit: "4", memory_limit: "8Gi" },
        staging: { cpu_limit: "8", memory_limit: "16Gi" },
        prod: { cpu_limit: "16", memory_limit: "32Gi" }
      },
      large: {
        dev: { cpu_limit: "8", memory_limit: "16Gi" },
        staging: { cpu_limit: "16", memory_limit: "32Gi" },
        prod: { cpu_limit: "32", memory_limit: "64Gi" }
      }
    },
    estimated_costs: {
      small: { dev: 0, staging: 0, prod: 0 },
      medium: { dev: 0, staging: 0, prod: 0 },
      large: { dev: 0, staging: 0, prod: 0 }
    },
    detection_patterns: [
      { pattern: /kubernetes|k8s|kubectl|helm/i, weight: 4 },
      { pattern: /deployment|pod|service|ingress/i, weight: 3 },
      { pattern: /KUBECONFIG|KUBERNETES_/i, weight: 5 },
      { pattern: /\.yaml.*kind:\s*(Deployment|Service)/i, weight: 5 }
    ]
  },

  "linux-vm": {
    name: "linux-vm",
    description: "Azure Linux VM with managed disks, security groups, and SSH key stored in Key Vault.",
    category: "single",
    components: ["linux-vm", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "Custom workloads requiring full VM control",
      "Legacy application hosting",
      "Development and testing environments",
      "Jump boxes and bastion hosts"
    ],
    config: {
      required: ["name", "subnet_id"],
      optional: {
        image_publisher: { type: "string", default: "Canonical", description: "OS image publisher" },
        image_offer: { type: "string", default: "0001-com-ubuntu-server-jammy", description: "OS image offer" },
        image_sku: { type: "string", default: "22_04-lts-gen2", description: "OS image SKU" },
        public_ip: { type: "boolean", default: false, description: "Attach public IP" },
        admin_username: { type: "string", default: "azureuser", description: "Admin username" }
      }
    },
    sizing: {
      small: {
        dev: { size: "Standard_B1s", os_disk_size_gb: 30 },
        staging: { size: "Standard_B2s", os_disk_size_gb: 64 },
        prod: { size: "Standard_D2s_v3", os_disk_size_gb: 128 }
      },
      medium: {
        dev: { size: "Standard_B2s", os_disk_size_gb: 64 },
        staging: { size: "Standard_D2s_v3", os_disk_size_gb: 128 },
        prod: { size: "Standard_D4s_v3", os_disk_size_gb: 256 }
      },
      large: {
        dev: { size: "Standard_D2s_v3", os_disk_size_gb: 128 },
        staging: { size: "Standard_D4s_v3", os_disk_size_gb: 256 },
        prod: { size: "Standard_D8s_v3", os_disk_size_gb: 512 }
      }
    },
    estimated_costs: {
      small: { dev: 8, staging: 30, prod: 70 },
      medium: { dev: 30, staging: 70, prod: 140 },
      large: { dev: 70, staging: 140, prod: 280 }
    },
    detection_patterns: [
      { pattern: /virtual.?machine|vm|server|compute/i, weight: 2 },
      { pattern: /ssh|linux|ubuntu|debian|centos|rhel/i, weight: 3 },
      { pattern: /ansible|puppet|chef|terraform.*vm/i, weight: 3 },
      { pattern: /bastion|jump.?box|gateway/i, weight: 4 }
    ]
  },

  "static-site": {
    name: "static-site",
    description: "Azure Static Web App for SPAs with optional API backend integration.",
    category: "single",
    components: ["static-web-app", "security-groups"],
    use_cases: [
      "Single-page applications (React, Vue, Angular)",
      "Static websites",
      "JAMstack applications",
      "Frontend hosting with API integration"
    ],
    config: {
      required: ["name"],
      optional: {
        repository_url: { type: "string", default: "", description: "GitHub repository URL for deployment" },
        branch: { type: "string", default: "main", description: "Branch to deploy from" },
        app_location: { type: "string", default: "/", description: "App source code location" },
        output_location: { type: "string", default: "dist", description: "Build output directory" }
      }
    },
    sizing: {
      small: {
        dev: { sku_tier: "Free", sku_size: "Free" },
        staging: { sku_tier: "Free", sku_size: "Free" },
        prod: { sku_tier: "Standard", sku_size: "Standard" }
      },
      medium: {
        dev: { sku_tier: "Free", sku_size: "Free" },
        staging: { sku_tier: "Standard", sku_size: "Standard" },
        prod: { sku_tier: "Standard", sku_size: "Standard" }
      },
      large: {
        dev: { sku_tier: "Standard", sku_size: "Standard" },
        staging: { sku_tier: "Standard", sku_size: "Standard" },
        prod: { sku_tier: "Standard", sku_size: "Standard" }
      }
    },
    estimated_costs: {
      small: { dev: 0, staging: 0, prod: 9 },
      medium: { dev: 0, staging: 9, prod: 9 },
      large: { dev: 9, staging: 9, prod: 9 }
    },
    detection_patterns: [
      { pattern: /react|vue|angular|svelte|next|nuxt|gatsby/i, weight: 3 },
      { pattern: /package\.json.*"build"/i, weight: 2 },
      { pattern: /static|spa|frontend|web.?app/i, weight: 1 },
      { pattern: /staticwebapp\.config\.json/i, weight: 6 }
    ]
  },

  // Composite patterns
  microservice: {
    name: "microservice",
    description: "AKS namespace with Event Hub and Storage for event-driven microservices. Includes RBAC and Key Vault.",
    category: "composite",
    components: ["aks-namespace", "eventhub", "storage-account", "keyvault", "security-groups", "rbac-assignments"],
    use_cases: [
      "Kubernetes microservices",
      "Event-driven services",
      "Container workloads",
      "Distributed systems"
    ],
    config: {
      required: ["name", "aks_cluster_name", "aks_resource_group"],
      optional: {
        enable_eventhub: { type: "boolean", default: true, description: "Include Event Hub" },
        enable_storage: { type: "boolean", default: true, description: "Include Storage Account" }
      }
    },
    sizing: {
      small: {
        dev: { cpu_limit: "2", memory_limit: "4Gi", eventhub_sku: "Basic" },
        staging: { cpu_limit: "2", memory_limit: "4Gi", eventhub_sku: "Basic" },
        prod: { cpu_limit: "4", memory_limit: "8Gi", eventhub_sku: "Standard" }
      },
      medium: {
        dev: { cpu_limit: "4", memory_limit: "8Gi", eventhub_sku: "Basic" },
        staging: { cpu_limit: "4", memory_limit: "8Gi", eventhub_sku: "Standard" },
        prod: { cpu_limit: "8", memory_limit: "16Gi", eventhub_sku: "Standard" }
      },
      large: {
        dev: { cpu_limit: "8", memory_limit: "16Gi", eventhub_sku: "Standard" },
        staging: { cpu_limit: "8", memory_limit: "16Gi", eventhub_sku: "Standard" },
        prod: { cpu_limit: "16", memory_limit: "32Gi", eventhub_sku: "Standard" }
      }
    },
    estimated_costs: {
      small: { dev: 15, staging: 45, prod: 120 },
      medium: { dev: 45, staging: 120, prod: 250 },
      large: { dev: 120, staging: 250, prod: 500 }
    },
    detection_patterns: [
      { pattern: /microservice|micro.?service/i, weight: 5 },
      { pattern: /kubernetes.*event/i, weight: 4 },
      { pattern: /distributed|event.*driven.*k8s/i, weight: 3 }
    ]
  },

  "web-app": {
    name: "web-app",
    description: "Static Web App frontend + Function App backend + PostgreSQL database. Full-stack web application pattern.",
    category: "composite",
    components: ["static-web-app", "function-app", "postgresql", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "Full-stack web applications",
      "SPA with API backend",
      "CRUD applications",
      "Traditional web apps"
    ],
    config: {
      required: ["name"],
      optional: {
        frontend_framework: { type: "string", default: "react", description: "Frontend framework" },
        api_runtime: { type: "string", default: "python", description: "API runtime" },
        database_version: { type: "string", default: "14", description: "PostgreSQL version" }
      }
    },
    sizing: {
      small: {
        dev: { frontend_sku: "Free", api_sku: "Y1", db_sku: "B_Standard_B1ms" },
        staging: { frontend_sku: "Free", api_sku: "Y1", db_sku: "B_Standard_B2s" },
        prod: { frontend_sku: "Standard", api_sku: "P1v2", db_sku: "GP_Standard_D2s_v3" }
      },
      medium: {
        dev: { frontend_sku: "Free", api_sku: "Y1", db_sku: "B_Standard_B2s" },
        staging: { frontend_sku: "Standard", api_sku: "P1v2", db_sku: "GP_Standard_D2s_v3" },
        prod: { frontend_sku: "Standard", api_sku: "P2v2", db_sku: "GP_Standard_D4s_v3" }
      },
      large: {
        dev: { frontend_sku: "Standard", api_sku: "B1", db_sku: "GP_Standard_D2s_v3" },
        staging: { frontend_sku: "Standard", api_sku: "P2v2", db_sku: "GP_Standard_D4s_v3" },
        prod: { frontend_sku: "Standard", api_sku: "P3v2", db_sku: "GP_Standard_D8s_v3" }
      }
    },
    estimated_costs: {
      small: { dev: 15, staging: 60, prod: 300 },
      medium: { dev: 60, staging: 300, prod: 550 },
      large: { dev: 200, staging: 550, prod: 1000 }
    },
    detection_patterns: [
      { pattern: /full.?stack|fullstack/i, weight: 5 },
      { pattern: /react.*api|vue.*backend|angular.*server/i, weight: 4 },
      { pattern: /frontend.*backend.*database/i, weight: 4 }
    ]
  },

  "api-backend": {
    name: "api-backend",
    description: "Function App API + SQL Database + Key Vault. Backend API pattern without frontend.",
    category: "composite",
    components: ["function-app", "azure-sql", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "REST API backends",
      "Mobile app backends",
      "B2B API services",
      "Internal APIs"
    ],
    config: {
      required: ["name"],
      optional: {
        runtime: { type: "string", default: "python", description: "Function runtime" },
        databases: { type: "array", default: [], description: "SQL databases to create" },
        enable_openapi: { type: "boolean", default: true, description: "Enable OpenAPI docs" }
      }
    },
    sizing: {
      small: {
        dev: { api_sku: "Y1", db_sku: "Basic" },
        staging: { api_sku: "Y1", db_sku: "S0" },
        prod: { api_sku: "P1v2", db_sku: "S1" }
      },
      medium: {
        dev: { api_sku: "Y1", db_sku: "S0" },
        staging: { api_sku: "P1v2", db_sku: "S1" },
        prod: { api_sku: "P2v2", db_sku: "S2" }
      },
      large: {
        dev: { api_sku: "B1", db_sku: "S1" },
        staging: { api_sku: "P2v2", db_sku: "S2" },
        prod: { api_sku: "P3v2", db_sku: "S3" }
      }
    },
    estimated_costs: {
      small: { dev: 5, staging: 30, prod: 130 },
      medium: { dev: 30, staging: 130, prod: 275 },
      large: { dev: 75, staging: 275, prod: 525 }
    },
    detection_patterns: [
      { pattern: /api.*backend|backend.*api/i, weight: 5 },
      { pattern: /rest.*api|graphql/i, weight: 3 },
      { pattern: /mobile.*backend|mobile.*api/i, weight: 4 }
    ]
  },

  "data-pipeline": {
    name: "data-pipeline",
    description: "Event Hub + Function App + Storage + MongoDB for data processing pipelines.",
    category: "composite",
    components: ["eventhub", "function-app", "storage-account", "mongodb", "keyvault", "security-groups", "rbac-assignments", "diagnostic-settings"],
    use_cases: [
      "ETL pipelines",
      "Real-time data processing",
      "Event streaming",
      "Data ingestion"
    ],
    config: {
      required: ["name"],
      optional: {
        input_hubs: { type: "array", default: ["input"], description: "Input event hubs" },
        output_hubs: { type: "array", default: ["output"], description: "Output event hubs" },
        storage_containers: { type: "array", default: ["raw", "processed"], description: "Storage containers" }
      }
    },
    sizing: {
      small: {
        dev: { eventhub_sku: "Basic", func_sku: "Y1", db_throughput: 400 },
        staging: { eventhub_sku: "Basic", func_sku: "Y1", db_throughput: 400 },
        prod: { eventhub_sku: "Standard", func_sku: "P1v2", db_throughput: 1000 }
      },
      medium: {
        dev: { eventhub_sku: "Basic", func_sku: "Y1", db_throughput: 400 },
        staging: { eventhub_sku: "Standard", func_sku: "P1v2", db_throughput: 1000 },
        prod: { eventhub_sku: "Standard", func_sku: "P2v2", db_throughput: 2000 }
      },
      large: {
        dev: { eventhub_sku: "Standard", func_sku: "B1", db_throughput: 1000 },
        staging: { eventhub_sku: "Standard", func_sku: "P2v2", db_throughput: 2000 },
        prod: { eventhub_sku: "Standard", func_sku: "P3v2", db_throughput: 4000 }
      }
    },
    estimated_costs: {
      small: { dev: 40, staging: 85, prod: 300 },
      medium: { dev: 85, staging: 300, prod: 550 },
      large: { dev: 200, staging: 550, prod: 1000 }
    },
    detection_patterns: [
      { pattern: /data.*pipeline|pipeline.*data/i, weight: 5 },
      { pattern: /etl|extract.*transform|data.*process/i, weight: 4 },
      { pattern: /streaming.*data|real.?time.*data/i, weight: 4 }
    ]
  }
};

// =============================================================================
// SIZING DEFAULTS
// =============================================================================

const SIZING_DEFAULTS = {
  environment_defaults: {
    dev: "small",
    staging: "medium",
    prod: "medium"
  },
  cost_limits: {
    dev: 500,
    staging: 2000,
    prod: 10000
  },
  conditional_features: {
    enable_diagnostics: { dev: false, staging: true, prod: true },
    enable_access_review: { dev: false, staging: false, prod: true },
    high_availability: { dev: false, staging: false, prod: true },
    geo_redundant_backup: { dev: false, staging: false, prod: true }
  }
};

// =============================================================================
// MCP SERVER
// =============================================================================

interface AnalysisResult {
  pattern: string;
  confidence: number;
  reasons: string[];
  suggested_config: Record<string, any>;
}

// Create the MCP server
const server = new Server(
  {
    name: "infrastructure-mcp-server",
    version: "2.0.0",
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
    name: "list_patterns",
    description: "List all available infrastructure patterns with their configuration options. Patterns are curated compositions that include all necessary infrastructure.",
    inputSchema: {
      type: "object",
      properties: {
        verbose: {
          type: "boolean",
          description: "Include detailed config options and sizing for each pattern",
          default: false
        },
        category: {
          type: "string",
          description: "Filter by category (single, composite)",
          enum: ["single", "composite"]
        }
      }
    }
  },
  {
    name: "analyze_codebase",
    description: "Analyze a codebase to detect what infrastructure pattern it needs. NOTE: This tool only works in LOCAL mode (stdio). When using the remote SSE server, use analyze_files instead.",
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
          description: "File patterns to include",
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
    name: "analyze_files",
    description: "Analyze file contents to detect infrastructure patterns. Use this when connecting to the remote MCP server. Useful files: package.json, requirements.txt, host.json, staticwebapp.config.json, source files with imports.",
    inputSchema: {
      type: "object",
      properties: {
        files: {
          type: "array",
          description: "Array of files with their contents",
          items: {
            type: "object",
            properties: {
              path: { type: "string", description: "Relative file path" },
              content: { type: "string", description: "File content" }
            },
            required: ["path", "content"]
          }
        },
        project_name: {
          type: "string",
          description: "Optional project name for context"
        }
      },
      required: ["files"]
    }
  },
  {
    name: "generate_pattern_request",
    description: "Generate a pattern request YAML file for provisioning infrastructure. This is the only way developers interact with the platform.",
    inputSchema: {
      type: "object",
      properties: {
        pattern: {
          type: "string",
          description: "Pattern name (e.g., 'keyvault', 'web-app', 'microservice')"
        },
        project: {
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
        owners: {
          type: "array",
          items: { type: "string" },
          description: "Array of owner email addresses for RBAC"
        },
        location: {
          type: "string",
          description: "Azure region",
          default: "eastus"
        },
        size: {
          type: "string",
          description: "T-shirt size (small, medium, large). Defaults based on environment.",
          enum: ["small", "medium", "large"]
        },
        config: {
          type: "object",
          description: "Pattern-specific configuration (name, optional settings)"
        }
      },
      required: ["pattern", "project", "business_unit", "owners", "config"]
    }
  },
  {
    name: "validate_pattern_request",
    description: "Validate a pattern request YAML configuration.",
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
    name: "get_pattern_details",
    description: "Get detailed information about a specific pattern including sizing, costs, and example usage.",
    inputSchema: {
      type: "object",
      properties: {
        pattern_name: {
          type: "string",
          description: "Name of the pattern (e.g., 'keyvault', 'web-app')"
        }
      },
      required: ["pattern_name"]
    }
  },
  {
    name: "estimate_cost",
    description: "Get estimated monthly cost for a pattern request.",
    inputSchema: {
      type: "object",
      properties: {
        pattern: {
          type: "string",
          description: "Pattern name"
        },
        environment: {
          type: "string",
          description: "Environment (dev, staging, prod)",
          default: "dev"
        },
        size: {
          type: "string",
          description: "T-shirt size (small, medium, large)"
        }
      },
      required: ["pattern"]
    }
  },
  {
    name: "generate_workflow",
    description: "Generate a GitHub Actions workflow file for infrastructure GitOps using patterns.",
    inputSchema: {
      type: "object",
      properties: {
        servicebus_namespace: {
          type: "string",
          description: "Azure Service Bus namespace",
          default: "sb-infra-api-rrkkz6a8"
        },
        github_org: {
          type: "string",
          description: "GitHub organization",
          default: "csGIT34"
        },
        tracking_url: {
          type: "string",
          description: "Infrastructure tracking dashboard URL",
          default: "https://wonderful-field-088efae10.1.azurestaticapps.net"
        }
      }
    }
  }
];

// Helper to get valid pattern names
function getValidPatterns(): string[] {
  return Object.keys(PATTERN_DEFINITIONS).sort();
}

// Tool handlers
async function listPatterns(verbose: boolean = false, category?: string): Promise<string> {
  let patterns = Object.values(PATTERN_DEFINITIONS);

  if (category) {
    patterns = patterns.filter(p => p.category === category);
  }

  if (verbose) {
    return JSON.stringify(patterns.map(p => ({
      name: p.name,
      description: p.description,
      category: p.category,
      components: p.components,
      use_cases: p.use_cases,
      config: {
        required: p.config.required,
        optional: Object.entries(p.config.optional).map(([key, opt]) => ({
          name: key,
          type: opt.type,
          default: opt.default,
          description: opt.description
        }))
      },
      sizing: p.sizing,
      estimated_costs: p.estimated_costs
    })), null, 2);
  }

  return JSON.stringify(patterns.map(p => ({
    name: p.name,
    description: p.description,
    category: p.category,
    components: p.components,
    use_cases: p.use_cases
  })), null, 2);
}

async function analyzeCodebase(
  targetPath: string,
  includePatterns: string[] = ["**/*.ts", "**/*.js", "**/*.tsx", "**/*.jsx", "**/*.py", "**/*.env*", "**/package.json"],
  excludePatterns: string[] = ["**/node_modules/**", "**/dist/**", "**/.git/**"]
): Promise<string> {
  const results: AnalysisResult[] = [];
  const detectedPatterns: Map<string, { matches: string[]; totalWeight: number }> = new Map();

  for (const patternName of Object.keys(PATTERN_DEFINITIONS)) {
    detectedPatterns.set(patternName, { matches: [], totalWeight: 0 });
  }

  try {
    const files = await glob(includePatterns, {
      cwd: targetPath,
      ignore: excludePatterns,
      absolute: true,
      nodir: true
    });

    for (const file of files.slice(0, 100)) {
      try {
        const content = fs.readFileSync(file, "utf-8");
        const relativePath = path.relative(targetPath, file);

        for (const [patternName, patternDef] of Object.entries(PATTERN_DEFINITIONS)) {
          for (const { pattern, weight } of patternDef.detection_patterns) {
            if (pattern.test(content) || pattern.test(relativePath)) {
              const detection = detectedPatterns.get(patternName)!;
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

    for (const [patternName, detection] of detectedPatterns) {
      if (detection.totalWeight > 0) {
        const confidence = Math.min(detection.totalWeight / 10, 1);
        const patternDef = PATTERN_DEFINITIONS[patternName];

        const suggestedConfig: Record<string, any> = {
          name: "my-" + patternName.replace(/-/g, "")
        };
        for (const [key, opt] of Object.entries(patternDef.config.optional)) {
          if (opt.default !== null && opt.default !== undefined) {
            suggestedConfig[key] = opt.default;
          }
        }

        results.push({
          pattern: patternName,
          confidence,
          reasons: detection.matches.slice(0, 5),
          suggested_config: suggestedConfig
        });
      }
    }

    results.sort((a, b) => b.confidence - a.confidence);

    return JSON.stringify({
      analyzed_path: targetPath,
      files_scanned: files.length,
      detected_patterns: results.slice(0, 5),
      summary: results.length > 0
        ? `Detected ${results.length} potential infrastructure patterns. Top recommendation: ${results[0].pattern}`
        : "No specific infrastructure patterns detected",
      hint: "Use generate_pattern_request with the recommended pattern to create your infrastructure.yaml"
    }, null, 2);

  } catch (error) {
    return JSON.stringify({
      error: `Failed to analyze codebase: ${error}`,
      analyzed_path: targetPath
    }, null, 2);
  }
}

function analyzeFiles(params: {
  files: Array<{ path: string; content: string }>;
  project_name?: string;
}): string {
  const { files, project_name } = params;

  if (!files || files.length === 0) {
    return JSON.stringify({
      error: "No files provided. Pass an array of {path, content} objects.",
      files_analyzed: 0
    }, null, 2);
  }

  const results: AnalysisResult[] = [];
  const patternDetections: Record<string, { matches: string[]; totalWeight: number }> = {};

  for (const file of files) {
    const { path: filePath, content } = file;
    if (!content) continue;

    const fileName = filePath.split('/').pop() || filePath;

    for (const [patternName, patternDef] of Object.entries(PATTERN_DEFINITIONS)) {
      for (const { pattern, weight } of patternDef.detection_patterns) {
        if (pattern.test(content) || pattern.test(fileName) || pattern.test(filePath)) {
          if (!patternDetections[patternName]) {
            patternDetections[patternName] = { matches: [], totalWeight: 0 };
          }
          const matchDescription = `${filePath}: matches ${pattern.source}`;
          if (!patternDetections[patternName].matches.includes(matchDescription)) {
            patternDetections[patternName].matches.push(matchDescription);
            patternDetections[patternName].totalWeight += weight;
          }
        }
      }
    }
  }

  for (const [patternName, detection] of Object.entries(patternDetections)) {
    const patternDef = PATTERN_DEFINITIONS[patternName];
    const confidence = Math.min(detection.totalWeight / 10, 1.0);

    if (confidence >= 0.2) {
      const suggestedConfig: Record<string, any> = {
        name: project_name ? project_name.toLowerCase().replace(/[^a-z0-9-]/g, "-") : "my-app"
      };
      for (const [key, opt] of Object.entries(patternDef.config.optional)) {
        if (opt.default !== null && opt.default !== undefined) {
          suggestedConfig[key] = opt.default;
        }
      }

      results.push({
        pattern: patternName,
        confidence,
        reasons: detection.matches.slice(0, 5),
        suggested_config: suggestedConfig
      });
    }
  }

  results.sort((a, b) => b.confidence - a.confidence);

  return JSON.stringify({
    project_name: project_name || "unknown",
    files_analyzed: files.length,
    detected_patterns: results.slice(0, 5),
    summary: results.length > 0
      ? `Detected ${results.length} potential patterns. Top recommendation: ${results[0].pattern}`
      : "No specific infrastructure patterns detected",
    hint: results.length > 0
      ? "Use generate_pattern_request with the recommended pattern"
      : "Try including more files: package.json, requirements.txt, host.json, source files with imports"
  }, null, 2);
}

function generatePatternRequest(params: {
  pattern: string;
  project: string;
  environment?: string;
  business_unit: string;
  owners: string[];
  location?: string;
  size?: string;
  config: Record<string, any>;
}): string {
  const patternDef = PATTERN_DEFINITIONS[params.pattern];
  if (!patternDef) {
    return JSON.stringify({
      error: `Unknown pattern '${params.pattern}'`,
      available_patterns: getValidPatterns()
    }, null, 2);
  }

  const environment = params.environment || "dev";
  const size = params.size || (SIZING_DEFAULTS.environment_defaults as any)[environment] || "small";

  // Check required config
  const missingRequired = patternDef.config.required.filter(r => !(r in params.config));
  if (missingRequired.length > 0) {
    return JSON.stringify({
      error: `Missing required config fields: ${missingRequired.join(", ")}`,
      required: patternDef.config.required,
      optional: Object.keys(patternDef.config.optional)
    }, null, 2);
  }

  const request = {
    version: "1",
    metadata: {
      project: params.project,
      environment,
      business_unit: params.business_unit,
      owners: params.owners,
      location: params.location || "eastus"
    },
    pattern: params.pattern,
    config: {
      ...params.config,
      size
    }
  };

  const yamlContent = YAML.stringify(request, { indent: 2 });

  // Get what will be provisioned
  const sizing = patternDef.sizing[size as keyof typeof patternDef.sizing]?.[environment as keyof SizingConfig] || {};
  const costs = patternDef.estimated_costs?.[size as keyof typeof patternDef.estimated_costs]?.[environment as keyof EnvironmentCosts] || "unknown";

  const header = `# Infrastructure Pattern Request
# Generated by Infrastructure MCP Server v2.0
#
# Pattern: ${params.pattern}
# Category: ${patternDef.category}
# Components: ${patternDef.components.join(", ")}
#
# Estimated monthly cost: $${costs}
# Size: ${size}
#
# What will be provisioned:
# - Resource Group: rg-${params.project}-${environment}
# - Security Groups with owner delegation
# - RBAC assignments for all components
${patternDef.components.includes("keyvault") ? `# - Key Vault with secrets management\n` : ""}${patternDef.components.includes("diagnostic-settings") ? `# - Diagnostic settings (staging/prod)\n` : ""}${patternDef.components.includes("access-review") && environment === "prod" ? `# - Access reviews (quarterly)\n` : ""}#

`;

  return header + yamlContent;
}

function validatePatternRequest(yamlContent: string): string {
  const errors: string[] = [];
  const warnings: string[] = [];

  try {
    const config = YAML.parse(yamlContent);

    // Validate metadata
    if (!config.metadata) {
      errors.push("Missing 'metadata' section");
    } else {
      const requiredMeta = ["project", "environment", "business_unit", "owners"];
      for (const field of requiredMeta) {
        if (!config.metadata[field]) {
          errors.push(`Missing metadata.${field}`);
        }
      }

      if (config.metadata.environment && !["dev", "staging", "prod"].includes(config.metadata.environment)) {
        warnings.push(`Environment '${config.metadata.environment}' is not standard (dev, staging, prod)`);
      }

      if (!Array.isArray(config.metadata.owners) || config.metadata.owners.length === 0) {
        errors.push("metadata.owners must be a non-empty array of email addresses");
      }
    }

    // Validate pattern
    if (!config.pattern) {
      errors.push("Missing 'pattern' field");
    } else if (!PATTERN_DEFINITIONS[config.pattern]) {
      errors.push(`Unknown pattern '${config.pattern}'. Valid patterns: ${getValidPatterns().join(", ")}`);
    } else {
      const patternDef = PATTERN_DEFINITIONS[config.pattern];
      const patternConfig = config.config || {};

      // Check required config
      for (const field of patternDef.config.required) {
        if (!(field in patternConfig)) {
          errors.push(`Missing required config.${field} for pattern '${config.pattern}'`);
        }
      }

      // Check unknown config options
      for (const key of Object.keys(patternConfig)) {
        if (!patternDef.config.required.includes(key) && !(key in patternDef.config.optional) && key !== "size") {
          warnings.push(`Unknown config option '${key}' for pattern '${config.pattern}'`);
        }
      }

      // Validate size
      const size = patternConfig.size;
      if (size && !["small", "medium", "large"].includes(size)) {
        errors.push(`Invalid size '${size}'. Must be: small, medium, or large`);
      }
    }

    // Compute what will be provisioned
    const provisioned: string[] = [];
    if (errors.length === 0 && config.pattern) {
      const patternDef = PATTERN_DEFINITIONS[config.pattern];
      const project = config.metadata.project;
      const env = config.metadata.environment;

      provisioned.push(`Resource Group: rg-${project}-${env}`);
      for (const component of patternDef.components) {
        provisioned.push(`Component: ${component}`);
      }

      if (env === "prod") {
        provisioned.push("Access reviews: enabled");
      }
      if (env !== "dev") {
        provisioned.push("Diagnostics: enabled");
      }
    }

    return JSON.stringify({
      valid: errors.length === 0,
      errors,
      warnings,
      provisioned_components: provisioned,
      summary: errors.length === 0
        ? (warnings.length > 0 ? "Valid with warnings" : "Valid")
        : `Invalid: ${errors.length} error(s)`
    }, null, 2);

  } catch (e) {
    return JSON.stringify({
      valid: false,
      errors: [`YAML parse error: ${e}`],
      warnings: [],
      provisioned_components: [],
      summary: "Invalid YAML syntax"
    }, null, 2);
  }
}

function getPatternDetails(patternName: string): string {
  const patternDef = PATTERN_DEFINITIONS[patternName];

  if (!patternDef) {
    return JSON.stringify({
      error: `Unknown pattern '${patternName}'`,
      available_patterns: getValidPatterns()
    }, null, 2);
  }

  const exampleYaml = `version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners:
    - alice@example.com
    - bob@example.com
  location: eastus

pattern: ${patternName}
config:
  name: my-${patternName.replace(/-/g, "")}
  size: small
${Object.entries(patternDef.config.optional)
  .filter(([_, opt]) => opt.default !== null && opt.default !== undefined && opt.default !== "" && !(Array.isArray(opt.default) && opt.default.length === 0))
  .map(([key, opt]) => `  # ${key}: ${typeof opt.default === "object" ? JSON.stringify(opt.default) : opt.default}  # ${opt.description}`)
  .join("\n")}`;

  return JSON.stringify({
    name: patternDef.name,
    description: patternDef.description,
    category: patternDef.category,
    components: patternDef.components,
    use_cases: patternDef.use_cases,
    config: {
      required: patternDef.config.required,
      optional: Object.entries(patternDef.config.optional).map(([key, opt]) => ({
        name: key,
        type: opt.type,
        default: opt.default,
        description: opt.description
      }))
    },
    sizing: patternDef.sizing,
    estimated_costs: patternDef.estimated_costs,
    example_yaml: exampleYaml
  }, null, 2);
}

function estimateCost(params: {
  pattern: string;
  environment?: string;
  size?: string;
}): string {
  const patternDef = PATTERN_DEFINITIONS[params.pattern];
  if (!patternDef) {
    return JSON.stringify({
      error: `Unknown pattern '${params.pattern}'`,
      available_patterns: getValidPatterns()
    }, null, 2);
  }

  const environment = params.environment || "dev";
  const size = params.size || (SIZING_DEFAULTS.environment_defaults as any)[environment] || "small";

  const costs = patternDef.estimated_costs;
  if (!costs) {
    return JSON.stringify({
      pattern: params.pattern,
      environment,
      size,
      error: "Cost estimates not available for this pattern"
    }, null, 2);
  }

  const cost = costs[size as keyof typeof costs]?.[environment as keyof EnvironmentCosts];

  return JSON.stringify({
    pattern: params.pattern,
    environment,
    size,
    estimated_monthly_cost_usd: cost,
    components: patternDef.components,
    note: "Actual costs may vary based on usage"
  }, null, 2);
}

function generateWorkflow(params: {
  servicebus_namespace?: string;
  github_org?: string;
  tracking_url?: string;
}): string {
  const servicebusNamespace = params.servicebus_namespace || "sb-infra-api-rrkkz6a8";
  const githubOrg = params.github_org || "csGIT34";
  const trackingUrl = params.tracking_url || "https://wonderful-field-088efae10.1.azurestaticapps.net";

  const validPatterns = JSON.stringify(getValidPatterns());

  const workflow = `# Infrastructure GitOps Workflow (Pattern-Based)
# Generated by Infrastructure MCP Server v2.0
#
# Required secrets:
#   INFRA_SERVICE_BUS_SAS_KEY - Service Bus SAS key
#   INFRA_APP_ID - GitHub App ID
#   INFRA_APP_PRIVATE_KEY - GitHub App private key
#
# Usage:
# 1. Create infrastructure.yaml with a pattern request
# 2. Create a PR to see the plan preview
# 3. Merge to main to provision resources

name: Infrastructure GitOps

on:
  push:
    branches:
      - main
    paths:
      - 'infrastructure.yaml'
  pull_request:
    paths:
      - 'infrastructure.yaml'

permissions:
  contents: read
  pull-requests: write

jobs:
  validate-and-plan:
    runs-on: ubuntu-latest
    outputs:
      validation_result: \${{ steps.validate.outputs.result }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install pyyaml requests

      - name: Validate infrastructure YAML
        id: validate
        run: |
          python << 'EOF'
          import yaml
          import json
          import sys
          import os

          infra_file = "infrastructure.yaml"

          if not os.path.exists(infra_file):
              print(f"::error::Infrastructure file not found: {infra_file}")
              with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
                  f.write("result=failed\\n")
              sys.exit(1)

          try:
              with open(infra_file, 'r') as f:
                  config = yaml.safe_load(f)
          except yaml.YAMLError as e:
              print(f"::error::Invalid YAML syntax: {e}")
              with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
                  f.write("result=failed\\n")
              sys.exit(1)

          errors = []

          # Validate metadata
          if 'metadata' not in config:
              errors.append("Missing 'metadata' section")
          else:
              metadata = config['metadata']
              required_meta = ['project', 'environment', 'business_unit', 'owners']
              for field in required_meta:
                  if field not in metadata:
                      errors.append(f"Missing metadata.{field}")
              if not isinstance(metadata.get('owners'), list) or len(metadata.get('owners', [])) == 0:
                  errors.append("metadata.owners must be a non-empty array")

          # Validate pattern
          valid_patterns = ${validPatterns}
          if 'pattern' not in config:
              errors.append("Missing 'pattern' field")
          elif config['pattern'] not in valid_patterns:
              errors.append(f"Unknown pattern '{config['pattern']}'. Valid: {', '.join(valid_patterns)}")

          # Validate config
          if 'config' not in config:
              errors.append("Missing 'config' section")
          elif 'name' not in config.get('config', {}):
              errors.append("Missing config.name")

          if errors:
              print("::error::Validation failed")
              for err in errors:
                  print(f"  - {err}")
              with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
                  f.write("result=failed\\n")
              sys.exit(1)

          print("Validation passed!")
          with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
              f.write("result=passed\\n")
          EOF

      - name: Generate Plan Preview
        id: plan
        run: |
          python << 'PLANEOF'
          import yaml
          import os

          with open("infrastructure.yaml", 'r') as f:
              config = yaml.safe_load(f)

          metadata = config['metadata']
          pattern = config['pattern']
          pattern_config = config.get('config', {})

          preview = "## Infrastructure Plan Preview\\n\\n"
          preview += "### Pattern Request\\n"
          preview += "| Property | Value |\\n|----------|-------|\\n"
          preview += f"| Pattern | \`{pattern}\` |\\n"
          preview += f"| Project | \`{metadata.get('project')}\` |\\n"
          preview += f"| Environment | \`{metadata.get('environment')}\` |\\n"
          preview += f"| Business Unit | \`{metadata.get('business_unit')}\` |\\n"
          preview += f"| Owners | \`{', '.join(metadata.get('owners', []))}\` |\\n"
          preview += f"| Location | \`{metadata.get('location', 'eastus')}\` |\\n"
          preview += f"| Size | \`{pattern_config.get('size', 'default')}\` |\\n\\n"

          preview += "### Configuration\\n"
          preview += "| Setting | Value |\\n|---------|-------|\\n"
          for key, value in pattern_config.items():
              preview += f"| {key} | \`{value}\` |\\n"

          preview += f"\\n### Resource Group\\n\`rg-{metadata.get('project')}-{metadata.get('environment')}\`\\n\\n"
          preview += "**On merge to main**, this pattern will be provisioned.\\n"
          preview += f"Track status at: ${trackingUrl}\\n"

          with open('plan_preview.md', 'w') as f:
              f.write(preview)
          print(preview)
          PLANEOF

      - name: Comment on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            let body = '## Infrastructure Plan\\n\\n';
            try {
              if (fs.existsSync('plan_preview.md')) {
                body = fs.readFileSync('plan_preview.md', 'utf8');
              }
            } catch (e) {
              body += 'Validation passed. See workflow summary for details.';
            }
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });
            const botComment = comments.find(c => c.user.type === 'Bot' && c.body.includes('Infrastructure Plan'));
            if (botComment) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: botComment.id,
                body: body
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body: body
              });
            }

  provision:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    needs: validate-and-plan

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install pyyaml

      - name: Submit to Infrastructure Queue
        env:
          SAS_KEY: \${{ secrets.INFRA_SERVICE_BUS_SAS_KEY }}
        run: |
          python << 'EOF'
          import yaml
          import json
          import hashlib
          import hmac
          import base64
          import time
          import urllib.parse
          import urllib.request
          import os

          with open("infrastructure.yaml", 'r') as f:
              yaml_content = f.read()
              config = yaml.safe_load(yaml_content)

          repo = os.environ.get('GITHUB_REPOSITORY', 'unknown')
          sha = os.environ.get('GITHUB_SHA', 'unknown')[:8]
          timestamp = int(time.time())
          request_id = f"gitops-{repo.replace('/', '-')}-{sha}-{timestamp}"

          namespace = "${servicebusNamespace}"
          queue_name = f"infrastructure-requests-{config['metadata']['environment']}"
          sas_key = os.environ['SAS_KEY']
          sas_key_name = "RootManageSharedAccessKey"

          uri = f"https://{namespace}.servicebus.windows.net/{queue_name}".lower()
          expiry = int(time.time()) + 3600
          string_to_sign = f"{urllib.parse.quote_plus(uri)}\\n{expiry}"
          signature = base64.b64encode(
              hmac.new(sas_key.encode('utf-8'), string_to_sign.encode('utf-8'), hashlib.sha256).digest()
          ).decode('utf-8')
          sas_token = f"SharedAccessSignature sr={urllib.parse.quote_plus(uri)}&sig={urllib.parse.quote_plus(signature)}&se={expiry}&skn={sas_key_name}"

          owners = config['metadata'].get('owners', [])
          primary_owner = owners[0] if owners else 'gitops@automation'
          message = {
              'request_id': request_id,
              'yaml_content': yaml_content,
              'requester_email': primary_owner,
              'metadata': {
                  'source': 'gitops',
                  'repository': repo,
                  'commit_sha': os.environ.get('GITHUB_SHA'),
                  'triggered_by': os.environ.get('GITHUB_ACTOR'),
                  'environment': config['metadata']['environment'],
                  'pattern': config['pattern'],
                  'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
              }
          }

          url = f"https://{namespace}.servicebus.windows.net/{queue_name}/messages"
          data = json.dumps(message).encode('utf-8')

          req = urllib.request.Request(url, data=data, method='POST')
          req.add_header('Authorization', sas_token)
          req.add_header('Content-Type', 'application/json')

          try:
              response = urllib.request.urlopen(req)
              print(f"Successfully submitted infrastructure request!")
              print(f"   Request ID: {request_id}")
              print(f"   Pattern: {config['pattern']}")
              print(f"   Queue: {queue_name}")
              print(f"\\nTrack status at: ${trackingUrl}")

          except urllib.error.HTTPError as e:
              print(f"::error::Failed to submit: {e.code} {e.reason}")
              print(e.read().decode())
              exit(1)
          EOF

      - name: Generate GitHub App Token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: \${{ secrets.INFRA_APP_ID }}
          private-key: \${{ secrets.INFRA_APP_PRIVATE_KEY }}
          owner: ${githubOrg}
          repositories: infrastructure-automation

      - name: Trigger Queue Consumer
        env:
          GH_TOKEN: \${{ steps.app-token.outputs.token }}
        run: |
          curl -X POST \\
            -H "Authorization: token \$GH_TOKEN" \\
            -H "Accept: application/vnd.github.v3+json" \\
            https://api.github.com/repos/${githubOrg}/infrastructure-automation/dispatches \\
            -d '{"event_type":"infrastructure-request","client_payload":{"source":"\${{ github.repository }}","pattern":"$(grep 'pattern:' infrastructure.yaml | awk '{print $2}')"}}'
          echo "Triggered infrastructure queue consumer"
`;

  return workflow;
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
      case "list_patterns":
        result = await listPatterns(args?.verbose as boolean, args?.category as string);
        break;

      case "analyze_codebase":
        result = await analyzeCodebase(
          args?.path as string,
          args?.include_patterns as string[],
          args?.exclude_patterns as string[]
        );
        break;

      case "analyze_files":
        result = analyzeFiles(args as {
          files: Array<{ path: string; content: string }>;
          project_name?: string;
        });
        break;

      case "generate_pattern_request":
        result = generatePatternRequest(args as any);
        break;

      case "validate_pattern_request":
        const yamlContent = args?.yaml_content as string ||
          (args?.file_path ? fs.readFileSync(args.file_path as string, "utf-8") : "");
        result = validatePatternRequest(yamlContent);
        break;

      case "get_pattern_details":
        result = getPatternDetails(args?.pattern_name as string);
        break;

      case "estimate_cost":
        result = estimateCost(args as { pattern: string; environment?: string; size?: string });
        break;

      case "generate_workflow":
        result = generateWorkflow(args as any);
        break;

      // Legacy support - redirect to new tools
      case "list_available_modules":
        result = await listPatterns(args?.verbose as boolean);
        break;

      case "generate_infrastructure_yaml":
        // Convert legacy params to new format
        const legacyParams = args as any;
        if (legacyParams.resources && legacyParams.resources.length > 0) {
          result = JSON.stringify({
            error: "Legacy resource-based requests are deprecated. Use generate_pattern_request with a pattern instead.",
            migration: "Instead of listing individual resources, choose a pattern that matches your use case. Use list_patterns to see available patterns.",
            example: "For a web app with database, use pattern: 'web-app' instead of listing static_web_app, function_app, and postgresql separately."
          }, null, 2);
        } else {
          result = JSON.stringify({ error: "Missing resources array" }, null, 2);
        }
        break;

      case "validate_infrastructure_yaml":
        result = validatePatternRequest(args?.yaml_content as string || "");
        break;

      case "get_module_details":
        result = getPatternDetails(args?.module_name as string);
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
  const mode = process.env.MCP_TRANSPORT || "stdio";
  const port = parseInt(process.env.PORT || "3000", 10);

  if (mode === "sse") {
    const app = express();
    app.use(cors());
    app.use(express.json());

    const apiKey = process.env.API_KEY;

    const validateApiKey = (req: any, res: any, next: any) => {
      if (!apiKey) {
        return next();
      }

      const authHeader = req.headers.authorization;
      let token: string | undefined;

      if (authHeader) {
        token = authHeader.startsWith("Bearer ")
          ? authHeader.slice(7)
          : authHeader;
      } else if (req.query.api_key) {
        token = req.query.api_key;
      }

      if (!token) {
        return res.status(401).json({ error: "Missing API key" });
      }

      if (token !== apiKey) {
        return res.status(403).json({ error: "Invalid API key" });
      }

      next();
    };

    // Health check
    app.get("/health", (req, res) => {
      res.json({
        status: "healthy",
        mode: "sse",
        version: "2.0.0",
        tools_count: tools.length,
        patterns_count: Object.keys(PATTERN_DEFINITIONS).length,
        auth: apiKey ? "enabled" : "disabled"
      });
    });

    // Pattern schema endpoint
    app.get("/schema/patterns", (req, res) => {
      res.json({
        valid_patterns: getValidPatterns(),
        patterns: Object.fromEntries(
          Object.entries(PATTERN_DEFINITIONS).map(([name, def]) => [
            name,
            {
              name: def.name,
              description: def.description,
              category: def.category,
              components: def.components,
              config_required: def.config.required,
              config_optional: Object.keys(def.config.optional)
            }
          ])
        ),
        generated_at: new Date().toISOString()
      });
    });

    // Sizing defaults endpoint
    app.get("/schema/sizing", (req, res) => {
      res.json({
        environment_defaults: SIZING_DEFAULTS.environment_defaults,
        cost_limits: SIZING_DEFAULTS.cost_limits,
        conditional_features: SIZING_DEFAULTS.conditional_features,
        sizes: ["small", "medium", "large"],
        generated_at: new Date().toISOString()
      });
    });

    // Legacy endpoint - redirect to patterns
    app.get("/schema/modules", (req, res) => {
      res.redirect(301, "/schema/patterns");
    });

    // Store active transports
    const transports = new Map<string, SSEServerTransport>();

    // SSE endpoint
    app.get("/sse", validateApiKey, (req: any, res: any) => {
      const clientApiKey = req.query.api_key ||
        (req.headers.authorization?.startsWith("Bearer ")
          ? req.headers.authorization.slice(7)
          : req.headers.authorization);

      let messagesEndpoint = "/messages";
      if (clientApiKey) {
        messagesEndpoint += `?api_key=${encodeURIComponent(clientApiKey)}`;
      }

      const transport = new SSEServerTransport(messagesEndpoint, res);
      const sessionId = (transport as any)._sessionId;

      transports.set(sessionId, transport);
      console.log(`[${sessionId.slice(0,8)}] New SSE connection, total: ${transports.size}`);

      const sessionServer = new Server(
        {
          name: "infrastructure-mcp-server",
          version: "2.0.0",
        },
        {
          capabilities: {
            tools: {},
          },
        }
      );

      sessionServer.setRequestHandler(ListToolsRequestSchema, async () => {
        return { tools };
      });

      sessionServer.setRequestHandler(CallToolRequestSchema, async (request) => {
        const { name, arguments: args } = request.params;

        try {
          let result: string;

          switch (name) {
            case "list_patterns":
              result = await listPatterns(args?.verbose as boolean, args?.category as string);
              break;
            case "analyze_codebase":
              result = await analyzeCodebase(args?.path as string, args?.include_patterns as string[], args?.exclude_patterns as string[]);
              break;
            case "analyze_files":
              result = analyzeFiles(args as { files: Array<{ path: string; content: string }>; project_name?: string; });
              break;
            case "generate_pattern_request":
              result = generatePatternRequest(args as any);
              break;
            case "validate_pattern_request":
              const yamlContent = args?.yaml_content as string || (args?.file_path ? fs.readFileSync(args.file_path as string, "utf-8") : "");
              result = validatePatternRequest(yamlContent);
              break;
            case "get_pattern_details":
              result = getPatternDetails(args?.pattern_name as string);
              break;
            case "estimate_cost":
              result = estimateCost(args as { pattern: string; environment?: string; size?: string });
              break;
            case "generate_workflow":
              result = generateWorkflow(args as any);
              break;
            // Legacy support
            case "list_available_modules":
              result = await listPatterns(args?.verbose as boolean);
              break;
            case "get_module_details":
              result = getPatternDetails(args?.module_name as string);
              break;
            default:
              throw new Error(`Unknown tool: ${name}`);
          }

          return { content: [{ type: "text", text: result }] };
        } catch (error) {
          return { content: [{ type: "text", text: `Error: ${error}` }], isError: true };
        }
      });

      sessionServer.connect(transport).then(() => {
        console.log(`[${sessionId.slice(0,8)}] Server connected`);
      }).catch((error) => {
        console.error(`[${sessionId.slice(0,8)}] Error:`, error);
      });

      req.on("close", () => {
        console.log(`[${sessionId.slice(0,8)}] Connection closed`);
        transports.delete(sessionId);
        sessionServer.close().catch(console.error);
      });
    });

    // Messages endpoint
    app.post("/messages", validateApiKey, async (req: any, res: any) => {
      const sessionId = req.query.sessionId as string;

      if (!sessionId) {
        return res.status(400).json({ error: "Missing sessionId" });
      }

      const transport = transports.get(sessionId);
      if (!transport) {
        return res.status(404).json({ error: "Session not found" });
      }

      try {
        await transport.handlePostMessage(req, res, req.body);
      } catch (error) {
        console.error(`[${sessionId.slice(0,8)}] Error:`, error);
        if (!res.headersSent) {
          res.status(500).json({ error: "Internal server error" });
        }
      }
    });

    app.listen(port, () => {
      console.log(`Infrastructure MCP Server v2.0 (Pattern-Based) running on http://0.0.0.0:${port}`);
      console.log(`SSE endpoint: http://0.0.0.0:${port}/sse`);
      console.log(`Patterns schema: http://0.0.0.0:${port}/schema/patterns`);
      console.log(`Sizing schema: http://0.0.0.0:${port}/schema/sizing`);
      console.log(`Health check: http://0.0.0.0:${port}/health`);
    });
  } else {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("Infrastructure MCP Server v2.0 (Pattern-Based) running on stdio");
  }
}

main().catch(console.error);
