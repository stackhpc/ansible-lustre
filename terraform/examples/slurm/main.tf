terraform {
  required_version = ">= 0.12, < 0.13"
}

provider "openstack" {
  cloud = "openstack"

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
  network_name = "demo-vxlan"
}


resource "openstack_blockstorage_volume_v3" "mgs" {
  name        = "mgs"
  description = "management volume"
  size        = 5
}
resource "openstack_compute_volume_attach_v2" "va_mgs" {
  instance_id = module.cluster.login_id
  volume_id   = openstack_blockstorage_volume_v3.mgs.id
}

resource "openstack_blockstorage_volume_v3" "mdt1" {
  name        = "mdt1"
  description = "metadata volume 1"
  size        = 5
}
resource "openstack_compute_volume_attach_v2" "va_mdt1" {
  instance_id = module.cluster.login_id
  volume_id   = openstack_blockstorage_volume_v3.mdt1.id
  depends_on  = ["openstack_compute_volume_attach_v2.va_mgs"]
}

resource "openstack_blockstorage_volume_v3" "ost1" {
  name        = "ost1"
  description = "storage target 1"
  size        = 50
}
resource "openstack_compute_volume_attach_v2" "va_ost1" {
  instance_id = module.cluster.login_id
  volume_id   = openstack_blockstorage_volume_v3.ost1.id
  depends_on  = ["openstack_compute_volume_attach_v2.va_mdt1"]
}
