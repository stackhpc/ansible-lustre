terraform {
  required_version = ">= 0.12, < 0.13"
}

provider "openstack" {
  version = "~> 1.25"
}
provider "local" {
  version = "~> 1.4"
}
provider "template" {
  version = "~> 2.1"
}

module "cluster" {
  source = "../../modules/cluster"

  compute_count = 1
  floatingip_pool = "CUDN-Private"
}
