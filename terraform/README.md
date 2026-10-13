# Terraform alternative

This folder uses the pinned `bpg/proxmox` provider `0.112.0`. The Registry's current documentation lists `0.112.0`; check the [versioned Registry page](https://registry.terraform.io/providers/bpg/proxmox/0.112.0/docs) before upgrading. The provider's upstream states its primary support target is Proxmox VE 9.x, with VE 8.x support but possible limitations: https://github.com/bpg/terraform-provider-proxmox

## Important

This is an **optional template-clone path**, not the interactive-ISO installer flow used by `scripts/deploy-guests.sh`. Do not use both paths for the same guests. It creates one Windows clone and one Ubuntu clone only when `enable_terraform_guests=true` and the existing, prepared template IDs / guest IDs / addresses / nodes / bridge / API details have been independently verified. It does not create the Proxmox nodes or form a cluster.

The Windows template must already be generalized and prepared with working drivers. Guest-side IP configuration may need to be done interactively for Windows. The Ubuntu template must support cloud-init and the configured public SSH key. Never provide a private key in Terraform configuration.

## Usage

Set values through environment variables or a local `terraform.tfvars` file, which is ignored by `.gitignore`. Recommended for secrets:

```bash
export TF_VAR_virtual_environment_endpoint='https://<verified-proxmox-node>:8006/'
export TF_VAR_virtual_environment_api_token='<least-privilege-token>'
```

Set `TF_VAR_enable_terraform_guests=true` only after cluster checks pass and fill all required variables. Use actual values from the `Envir` inventory and live Proxmox state; no guest IDs, subnet, gateway, DNS, storage or bridge is assumed here.

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out=lab.tfplan
terraform show lab.tfplan
# Review changes and apply interactively (no -auto-approve):
terraform apply lab.tfplan
```

The provider `api_token` must not be committed or placed in `terraform.tfvars` for this repository. Terraform state can contain sensitive values and is ignored by Git; protect it and do not share it. Avoid `terraform destroy` unless separately reviewed and explicitly intended. Use a limited API token and valid TLS certificates; `insecure=false` is intentional.
