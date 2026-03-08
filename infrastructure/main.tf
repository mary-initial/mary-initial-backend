variable "appId" {
  description = "Azure Kubernetes Service Cluster service principal"
}

variable "password" {
  description = "Azure Kubernetes Service Cluster password"
  sensitive   = true
}

variable "image-tag" {
  description = "Image tag of the version to deploy"
}

variable "ghcr_username" {
  description = "GitHub Container Registry username"
}

variable "ghcr_token" {
  description = "GitHub Container Registry token"
  sensitive   = true
}

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
    container_name   = "tfstate" # Can be passed via `-backend-config=`"container_name=<container name>"` in the `init` command.

    # tenant_id        = "00000000-0000-0000-0000-000000000000" # Set via `ARM_TENANT_ID` environment variable.
    # client_id        = "00000000-0000-0000-0000-000000000000" # Set via `ARM_CLIENT_ID` environment variable.
    # storage_account_name = "handykidtfstate" # Passed via `-backend-config=`"storage_account_name=<storage account name>"` in the `init` command.
    # key                  = "dev.tfstate" # Passed via `-backend-config=`"key=<blob key name>"` in the `init` command.
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.61.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }

  required_version = ">= 1.14.0"
}

provider "azurerm" {
  features {}
}


resource "random_pet" "prefix" {}

resource "azurerm_resource_group" "default" {
  name     = "${random_pet.prefix.id}-rg"
  location = "westeurope"

  tags = {
    environment = "Demo"
    created_by  = "Terraform"
  }
}

resource "azurerm_storage_account" "terraform_state" {
  name                       = "${replace(random_pet.prefix.id, "-", "")}tfstate"
  resource_group_name        = azurerm_resource_group.default.name
  location                   = azurerm_resource_group.default.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  account_kind               = "BlobStorage"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  blob_properties {
    versioning_enabled = true
    container_delete_retention_policy {
      days = 90
    }
  }

  tags = {
    environment = "Demo"
    created_by  = "Terraform"
  }
}

resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.terraform_state.id
  container_access_type = "private"
}

resource "azurerm_kubernetes_cluster" "default" {
  name                = "${random_pet.prefix.id}-aks"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  dns_prefix          = "${random_pet.prefix.id}-k8s"
  kubernetes_version  = "1.34"

  # This is added because otherwise terraform kept adding and removing it.
  oidc_issuer_enabled = true

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_D2_v4"
    os_disk_size_gb = 30

    # These are added because otherwise terraform kept adding and removing them.
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  service_principal {
    client_id     = var.appId
    client_secret = var.password
  }

  role_based_access_control_enabled = true

  tags = {
    environment = "Demo"
    created_by  = "Terraform"
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.default.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].client_key)
}

resource "kubernetes_deployment_v1" "backend" {
  metadata {
    name = "demo-deployment"
    labels = {
      app        = "wip"
      created_by = "Terraform"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "wip"
      }
    }
    template {
      metadata {
        labels = {
          app        = "wip"
          created_by = "Terraform"
        }
      }
      spec {
        container {
          image = "ghcr.io/mary-initial/mary-initial-backend/backend:${var.image-tag}"
          env {
            name  = "PORT"
            value = 8000
          }

          name = "backend"
          port {
            container_port = 8000
          }
        }
        image_pull_secrets {
          name = kubernetes_secret_v1.ghcr.metadata[0].name
        }
      }
    }
  }
}

resource "kubernetes_secret_v1" "ghcr" {
  metadata {
    name = "ghcr-secret"
    labels = {
      created_by = "Terraform"
    }
  }
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_token
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }
  type = "kubernetes.io/dockerconfigjson"
}


resource "kubernetes_service_v1" "backend" {
  metadata {
    name = "backend"
    labels = {
      created_by = "Terraform"
    }
  }

  spec {
    selector = {
      app = kubernetes_deployment_v1.backend.spec[0].selector[0].match_labels.app
    }

    port {
      port        = 80
      target_port = 8000
    }

    type = "LoadBalancer"
  }
}

output "resource_group_name" {
  value = azurerm_resource_group.default.name
}

output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.default.name
}

# output "host" {
#   value     = azurerm_kubernetes_cluster.default.kube_config.0.host
#   sensitive = true
# }

output "backend_ip" {
  description = "Public IP address of the backend service"
  value       = kubernetes_service_v1.backend.status[0].load_balancer[0].ingress[0].ip
}
