variable "appId" {
  description = "Azure Kubernetes Service Cluster service principal"
}

variable "password" {
  description = "Azure Kubernetes Service Cluster password"
  sensitive   = true
}

variable "image_tag" {
  description = "Image tag of the version to deploy"
}

variable "ghcr_username" {
  description = "GitHub Container Registry username"
}

variable "ghcr_token" {
  description = "GitHub Container Registry token"
  sensitive   = true
}

variable "basic_auth" {
  description = "The username and password in .htpasswd format"
  sensitive   = true
}

variable "storybook_image_tag" {
  description = "Image tag of the storybook image to deploy."
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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
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

## Store the terraform state.

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

## Create the azure kubernetes cluster.

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

## Add the CRDs for the packages we use cluster-wide

provider "helm" {
  kubernetes = {
    load_config_file       = false
    host                   = azurerm_kubernetes_cluster.default.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].cluster_ca_certificate)
    client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].client_key)
  }
}

resource "helm_release" "envoy" {
  name             = "envoy"
  chart            = "oci://docker.io/envoyproxy/gateway-helm"
  create_namespace = true
  version          = "v1.7.1"
  timeouts = {
    # this took more than the default timeout in the dev cluster, which made terraform time out.
    create = "15m"
    update = "15m"
  }
}

resource "helm_release" "cert_manager" {
  # Envoy's custom resource definitions must load first.
  depends_on       = [helm_release.envoy]
  name             = "cert-manager"
  chart            = "oci://quay.io/jetstack/charts/cert-manager:v1.20.0"
  version          = "v1.20.0"
  namespace        = "cert-manager"
  create_namespace = true
  set = [
    { name = "crds.enabled", value = true },
    # { name = "config.apiVersion", value = "controller.config.cert-manager.io/v1alpha1" },
    { name = "config.enableGatewayAPI", value = true }
  ]
  timeouts = {
    # this took ~8 minutes in the dev cluster, which made terraform time out.
    create = "15m"
  }
}

resource "helm_release" "marys" {
  depends_on       = [helm_release.cert_manager]
  name             = "marys"
  chart            = "./marys-helm-chart"
  namespace        = "default"
  create_namespace = true
  set = [{
    name  = "backend.image_tag",
    value = var.image_tag
    }, {
    name  = "storybook.image_tag",
    value = var.storybook_image_tag
    }, {
    name  = "ghcr_username",
    value = var.ghcr_username
    }, {
    name  = "ghcr_token",
    value = var.ghcr_token
    }, {
    name  = "hostname",
    value = "test.marys.dk"
    }, {
    name  = "basic_auth",
    value = var.basic_auth
  }]
}

output "resource_group_name" {
  value = azurerm_resource_group.default.name
}

output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.default.name
}

# Useful when you want to get the kubeconfig locally.
# output "host" {
#   value     = azurerm_kubernetes_cluster.default.kube_config.0.host
#   sensitive = true
# }
