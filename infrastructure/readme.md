# Infrastructure

Follow the instructions at <https://developer.hashicorp.com/terraform/tutorials/azure-get-started/install-cli> to install terraform.

Make sure you're logged in to azure:

```sh
az login
```

Copy `template.env` to `.env` and put in the correct values (get from Jakob Vase).

Setup the repository:

```sh
terraform init
```

Validate and format:

```sh
terraform fmt
terraform validate
```

Apply changes:

```sh
terraform apply
```

See much more at <https://developer.hashicorp.com/terraform>.

## Setup diary

Followed <https://developer.hashicorp.com/terraform/tutorials/azure-get-started/install-cli> to setup terraform.

Followed <https://developer.hashicorp.com/terraform/tutorials/kubernetes/aks> to set up the kubernetes cluster.

Read about variables in https://developer.hashicorp.com/terraform/tutorials/configuration-language/variables and https://developer.hashicorp.com/terraform/language/values/variables#assigning-values-to-root-module-variables.

Need to find a template terraform .gitignore. Added one from https://github.com/github/gitignore/blob/main/Terraform.gitignore.

Reading https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster and https://github.com/hashicorp/terraform-provider-azurerm/tree/main/examples/kubernetes to understand how to set up kubernetes.

I now have a hopefully working kubernetes cluster setup. I need to get an image into ghcr.io now, so I'll set up github actions now.

Github action set up and it pushed to ghcr.io correctly. Now to make the kubernetes deployment work.

TODO seems like I need to use helm (https://registry.terraform.io/providers/hashicorp/helm/latest/docs) if I want to run stuff like harbor in the cluster. Which I do, but really already?

TODO need to read this https://developer.hashicorp.com/terraform/language/manage-sensitive-data.

TODO check the size of the node. It can be pretty small.

TODO set up argocd?
