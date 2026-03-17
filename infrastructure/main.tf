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

variable "basic_auth" {
  description = "The username and password in .htpasswd format"
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
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.default.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config[0].client_key)
}

resource "kubernetes_manifest" "gateway_class" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "eg"
    }
    spec = {
      controllerName = "gateway.envoyproxy.io/gatewayclass-controller"
    }
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

resource "kubernetes_manifest" "certificate_issuer" {
  manifest = yamldecode(<<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: helle.holm.clausen@regionh.dk
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          # So weird but this works. See https://hackmd.io/@maelvls/test-xlistenerset. Found it through https://github.com/cert-manager/cert-manager/issues/7473.
          gatewayHTTPRoute: {}
EOF
  )
}

resource "kubernetes_manifest" "gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "eg"
      namespace = "default"
      annotations = {
        "cert-manager.io/cluster-issuer" = "letsencrypt"
      }
    }
    spec = {
      gatewayClassName = "eg"
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          hostname = "test.marys.dk"
          port     = 80
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https"
          protocol = "HTTPS"
          hostname = "test.marys.dk"
          port     = 443
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              kind = "Secret"
              name = "eg-https"
            }]
          }
        }
      ]
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

resource "kubernetes_secret_v1" "basic_auth" {
  metadata {
    # I think this is referenced from basic_auth_security_policy
    name = "basic-auth"
    labels = {
      created_by = "Terraform"
    }
  }

  data = {
    ".htpasswd" = var.basic_auth
  }
}

resource "kubernetes_manifest" "basic_auth_security_policy" {
  manifest = yamldecode(<<-EOT
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: SecurityPolicy
    metadata:
      name: basic-auth
      namespace: "default"
    spec:
      targetRefs:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
          name: backend
      basicAuth:
        users:
          name: "basic-auth"
  
    EOT
  )
}

resource "kubernetes_service_account_v1" "backend" {
  metadata {
    name = "backend"
  }
}

resource "kubernetes_service_v1" "backend" {
  metadata {
    name = "backend"
    labels = {
      created_by = "Terraform"
      app        = "wip"
      service    = "backend"
    }
  }

  spec {
    selector = {
      app = "wip"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
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
            value = 8080
          }

          name = "backend"
          port {
            container_port = 8080
          }
        }
        image_pull_secrets {
          name = kubernetes_secret_v1.ghcr.metadata[0].name
        }
      }
    }
  }
}

resource "kubernetes_manifest" "http_route" {
  manifest = yamldecode(<<EOT
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: backend
  namespace: default
spec:
  parentRefs:
    - name: eg
  hostnames:
    - "test.marys.dk"
  rules:
    - backendRefs:
        - name: backend
          port: 8080
EOT
  )
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

# Useful when you want to see the backend's ip, in case that changes.
# output "backend_ip" {
#   description = "Public IP address of the backend service"
#   value       = kubernetes_service_v1.backend.status[0].load_balancer[0].ingress[0].ip
# }
