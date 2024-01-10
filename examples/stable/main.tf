# the GITHUB_TOKEN environment variable must be set for this example to work
provider "github" {}

provider "aws" {
  default_tags {
    tags = {
      ID = local.identifier
    }
  }
}

locals {
  email          = "terraform-ci@suse.com"
  identifier     = var.identifier
  name           = "tf-install-stable-${local.identifier}"
  username       = "tf-${local.identifier}"
  rke2_version   = var.rke2_version # I want ci to be able to get the latest version of rke2 to test
  public_ssh_key = var.key          # I don't normally recommend using variables in root modules, but it allows tests to supply their own key
  key_name       = var.key_name     # A lot of troubleshooting during critical times can be saved by hard coding variables in root modules
  # root modules should be secured properly (including the state), and should represent your running infrastructure
}

# selecting the vpc, subnet, and ssh key pair, generating a security group specific to the ci runner, and allowing egress traffic (no ingress)
# this enables rpm install method
module "aws_access" {
  source              = "rancher/access/aws"
  version             = "v0.1.4"
  owner               = local.email
  vpc_name            = "default"
  subnet_name         = "default"
  security_group_name = local.name
  security_group_type = "egress" # https://github.com/rancher/terraform-aws-access/blob/main/modules/security_group/types.tf
  ssh_key_name        = local.key_name
}

module "aws_server" {
  depends_on          = [module.aws_access]
  source              = "rancher/server/aws"
  version             = "v0.1.1"
  image               = "rhel-9" # https://github.com/rancher/terraform-aws-server/blob/main/modules/image/types.tf
  owner               = local.email
  name                = local.name
  type                = "medium" # https://github.com/rancher/terraform-aws-server/blob/main/modules/server/types.tf
  user                = local.username
  ssh_key             = local.public_ssh_key
  ssh_key_name        = local.key_name
  subnet_name         = "default"
  security_group_name = module.aws_access.security_group_name
}

resource "random_uuid" "join_token" {}

# the idea here is to provide the least amount of config necessary to get a cluster up and running
# if a user wants to provide their own config, they can put it in the local_file_path or supply it as a string
module "config" {
  depends_on = [
    module.aws_access,
    module.aws_server,
    random_uuid.join_token,
  ]
  source            = "rancher/rke2-config/local"
  version           = "v0.1.1"
  advertise-address = module.aws_server.private_ip
  tls-san           = [module.aws_server.public_ip, module.aws_server.private_ip]
  node-external-ip  = [module.aws_server.public_ip]
  node-ip           = [module.aws_server.private_ip]
  local_file_path   = "${path.root}/rke2"
  local_file_name   = "50-${local.identifier}.yaml"
  token             = random_uuid.join_token.result
}

module "stable_install" {
  depends_on = [
    module.aws_access,
    module.aws_server,
    random_uuid.join_token,
    module.config,
  ]
  source = "../../" # change this to "rancher/rke2-install/null" per https://registry.terraform.io/modules/rancher/rke2-install/null/latest
  # version = "v0.2.7" # when using this example you will need to set the version
  ssh_ip             = module.aws_server.public_ip
  ssh_user           = local.username
  release            = local.rke2_version
  local_file_path    = "${path.root}/rke2"
  install_method     = "rpm"
  server_prep_script = file("${path.root}/prep.sh")
  identifier = md5(join("-", [
    # if any of these things change, redeploy rke2
    module.aws_server.id,
    local.rke2_version,
    module.config.yaml_config,
  ]))
}
