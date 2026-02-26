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
