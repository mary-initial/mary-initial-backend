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

          name = "backend"
          port {
            container_port = 80
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
      target_port = 80
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
