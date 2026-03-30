# Infrastructure

Follow the instructions at <https://developer.hashicorp.com/terraform/tutorials/azure-get-started/install-cli> to install terraform.

Make sure you're logged in to azure:

```sh
az login
```

Copy `template.env` to `.env` and put in the correct values (get from Jakob Vase).

Copy `terraform.template.tfvars` to `terraform.tfvars` and put in the correct values.

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
