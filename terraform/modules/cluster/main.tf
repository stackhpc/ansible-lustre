terraform {
  required_version = ">= 0.12, < 0.13"
}

resource "openstack_compute_keypair_v2" "terraform" {
  name       = "terraform_${var.instance_prefix}"
  public_key = file("${var.ssh_key_file}.pub")
}

resource "openstack_compute_instance_v2" "login" {
  name = "${var.instance_prefix}-login"
  image_name = var.image
  flavor_name = var.flavor
  key_pair = openstack_compute_keypair_v2.terraform.name
  security_groups = ["default"]
  network {
    name = var.network_name
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = var.floatingip_pool
}

resource "openstack_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = "${openstack_networking_floatingip_v2.fip_1.address}"
  instance_id = "${openstack_compute_instance_v2.login.id}"
}


resource "openstack_compute_instance_v2" "compute" {
  count = "${var.compute_count}"
  name = "${format("${var.instance_prefix}-comp%02d", count.index+1)}"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    name = "${var.network_name}"
  }
}


resource "openstack_networking_network_v2" "net2" {
  name           = "net2"
  admin_state_up = "true"
}
resource "openstack_networking_subnet_v2" "net2" {
  name            = "net2"
  network_id      = "${openstack_networking_network_v2.net2.id}"
  cidr            = "192.168.42.0/24"
  ip_version      = 4
}
resource "openstack_networking_router_v2" "net2" {
  name                = "net2"
  admin_state_up      = "true"
  external_network_id = "${data.openstack_networking_network_v2.internet.id}"
}
resource "openstack_networking_router_interface_v2" "net2" {
  router_id = "${openstack_networking_router_v2.net2.id}"
  subnet_id = "${openstack_networking_subnet_v2.net2.id}"
}


resource "openstack_compute_instance_v2" "client2" {
  name = "${var.instance_prefix}-client2"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    uuid = "${openstack_networking_network_v2.net2.id}"
  }
}
resource "openstack_networking_floatingip_v2" "fip_2" {
  pool = "${var.floatingip_pool}"
}
resource "openstack_compute_floatingip_associate_v2" "fip_2" {
  floating_ip = "${openstack_networking_floatingip_v2.fip_2.address}"
  instance_id = "${openstack_compute_instance_v2.client2.id}"
}


resource "openstack_compute_instance_v2" "lnet2" {
  name = "${var.instance_prefix}-lnet2"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  config_drive = true
  network {
    name = "${var.network_name}"
  }
  network {
    uuid = "${openstack_networking_network_v2.net2.id}"
  }
}


resource "openstack_compute_instance_v2" "lustre_server" {
  name = "${var.instance_prefix}-storage"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    name = "${var.network_name}"
  }
}

resource "openstack_blockstorage_volume_v3" "mgs" {
  name        = "mgs"
  description = "management volume"
  size        = 5
}
resource "openstack_compute_volume_attach_v2" "va_mgs" {
  instance_id = openstack_compute_instance_v2.lustre_server.id
  volume_id   = openstack_blockstorage_volume_v3.mgs.id
}

resource "openstack_blockstorage_volume_v3" "mdt1" {
  name        = "mdt1"
  description = "metadata volume 1"
  size        = 5
}
resource "openstack_compute_volume_attach_v2" "va_mdt1" {
  instance_id = openstack_compute_instance_v2.lustre_server.id
  volume_id   = openstack_blockstorage_volume_v3.mdt1.id
  depends_on  = [openstack_compute_volume_attach_v2.va_mgs]
}

resource "openstack_blockstorage_volume_v3" "ost1" {
  name        = "ost1"
  description = "storage target 1"
  size        = 50
}
resource "openstack_compute_volume_attach_v2" "va_ost1" {
  instance_id = openstack_compute_instance_v2.lustre_server.id
  volume_id   = openstack_blockstorage_volume_v3.ost1.id
  depends_on  = [openstack_compute_volume_attach_v2.va_mdt1]
}



data  "template_file" "ohpc" {
    template = "${file("${path.module}/inventory.tpl")}"
    vars = {
      storage = <<EOT
${openstack_compute_instance_v2.lustre_server.name} ansible_host=${openstack_compute_instance_v2.lustre_server.network[0].fixed_ip_v4}
EOT
      net1 = <<EOT
%{for compute in openstack_compute_instance_v2.compute}
${compute.name} ansible_host=${compute.network[0].fixed_ip_v4}%{ endfor }
EOT
      lnet2 = <<EOT
${openstack_compute_instance_v2.lnet2.name} ansible_host=${openstack_compute_instance_v2.lnet2.network[0].fixed_ip_v4} eth1_address=${openstack_compute_instance_v2.lnet2.network[1].fixed_ip_v4}
EOT
      net2 = <<EOT
${openstack_compute_instance_v2.client2.name} ansible_host=${openstack_compute_instance_v2.client2.network[0].fixed_ip_v4}
EOT
      fip_net1 = "${openstack_networking_floatingip_v2.fip_1.address}"
      fip_net2 = "${openstack_networking_floatingip_v2.fip_2.address}"
      ssh_user_name = "${var.ssh_user_name}"
    }
    depends_on = [openstack_compute_instance_v2.compute]
}

resource "local_file" "hosts" {
  content  = "${data.template_file.ohpc.rendered}"
  filename = "${path.cwd}/ansible_inventory"
}
