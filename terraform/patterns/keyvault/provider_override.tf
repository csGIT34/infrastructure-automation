# Local testing override
provider "azurerm" {
  features {}
}

provider "azuread" {}

provider "msgraph" {
  use_cli = true
}
