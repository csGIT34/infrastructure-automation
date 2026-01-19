terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    use_oidc = true
  }
}

# Generate a secure API key
resource "random_password" "api_key" {
  length  = 32
  special = false
}

provider "azurerm" {
  features {}
  use_oidc = true
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "container_registry" {
  description = "Container registry URL"
  type        = string
}

locals {
  name_prefix = "mcp-${var.environment}"
  common_tags = {
    Environment = var.environment
    Service     = "infrastructure-mcp-server"
    ManagedBy   = "Terraform"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for Container Apps
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${local.name_prefix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.common_tags
}

# Container App
resource "azurerm_container_app" "mcp_server" {
  name                         = "ca-${local.name_prefix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  secret {
    name  = "api-key"
    value = random_password.api_key.result
  }

  template {
    min_replicas = 0
    max_replicas = 3

    container {
      name   = "mcp-server"
      image  = "${var.container_registry}/infrastructure-mcp-server:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "MCP_TRANSPORT"
        value = "sse"
      }

      env {
        name  = "PORT"
        value = "3000"
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name        = "API_KEY"
        secret_name = "api-key"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 3000
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 3000
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "http2" # Better for SSE/streaming

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# Outputs
output "mcp_server_url" {
  description = "MCP Server URL"
  value       = "https://${azurerm_container_app.mcp_server.ingress[0].fqdn}"
}

output "mcp_sse_endpoint" {
  description = "MCP SSE endpoint for Claude Code"
  value       = "https://${azurerm_container_app.mcp_server.ingress[0].fqdn}/sse"
}

output "health_endpoint" {
  description = "Health check endpoint"
  value       = "https://${azurerm_container_app.mcp_server.ingress[0].fqdn}/health"
}

output "api_key" {
  description = "API key for MCP server authentication"
  value       = random_password.api_key.result
  sensitive   = true
}

output "claude_code_config" {
  description = "Claude Code MCP configuration (use 'terraform output -raw api_key' to get the key)"
  value = jsonencode({
    mcpServers = {
      infrastructure = {
        type = "sse"
        url  = "https://${azurerm_container_app.mcp_server.ingress[0].fqdn}/sse"
        requestInit = {
          headers = {
            Authorization = "Bearer <API_KEY>"
          }
        }
      }
    }
  })
}
