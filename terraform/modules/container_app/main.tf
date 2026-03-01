# terraform/modules/container_app/main.tf
# Creates an Azure Container App with optional Container App Environment

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Container App Environment (created if not provided)
resource "azurerm_container_app_environment" "main" {
  count = var.container_app_environment_id == null ? 1 : 0

  name                = var.environment_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

locals {
  environment_id = var.container_app_environment_id != null ? var.container_app_environment_id : azurerm_container_app_environment.main[0].id
}

resource "azurerm_container_app" "main" {
  name                         = var.name
  container_app_environment_id = local.environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = var.revision_mode
  tags                         = var.tags

  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.container_name != null ? var.container_name : var.name
      image  = var.container_image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  dynamic "ingress" {
    for_each = var.enable_ingress ? [1] : []
    content {
      external_enabled = var.external_ingress
      target_port      = var.target_port
      transport        = "auto"

      traffic_weight {
        percentage      = 100
        latest_revision = true
      }
    }
  }
}
