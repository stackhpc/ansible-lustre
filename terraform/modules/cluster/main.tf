terraform {
  required_version = ">= 0.12, < 0.13"
}

resource "openstack_compute_keypair_v2" "terraform" {
  name       = "terraform_${var.instance_prefix}"
  public_key = file("${var.ssh_key_file}.pub")
}

# --- net 1 ---
resource "openstack_networking_network_v2" "net1" {
  name           = "net1"
  admin_state_up = "true"
}
resource "openstack_networking_subnet_v2" "net1" {
  name            = "net1"
  network_id      = "${openstack_networking_network_v2.net1.id}"
  cidr            = "192.168.41.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"] #["131.111.8.42, 131.111.12.20]
  ip_version      = 4
}
resource "openstack_networking_router_v2" "external" {
  name                = "external"
  admin_state_up      = "true"
  external_network_id = "${data.openstack_networking_network_v2.internet.id}"
}
resource "openstack_networking_router_interface_v2" "net1" {
  router_id = "${openstack_networking_router_v2.external.id}"
  subnet_id = "${openstack_networking_subnet_v2.net1.id}"
}


resource "openstack_compute_instance_v2" "client1" {
  name = "${var.instance_prefix}-client1"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    uuid = "${openstack_networking_network_v2.net1.id}"
  }
}

# --- net 2 ---
resource "openstack_networking_network_v2" "net2" {
  name           = "net2"
  admin_state_up = "true"
}
resource "openstack_networking_subnet_v2" "net2" {
  name            = "net2"
  network_id      = "${openstack_networking_network_v2.net2.id}"
  cidr            = "192.168.42.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"] #["131.111.8.42, 131.111.12.20]
  ip_version      = 4
}
resource "openstack_networking_router_interface_v2" "net2" {
  router_id = "${openstack_networking_router_v2.external.id}"
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


resource "openstack_compute_instance_v2" "lnet2" {
  name = "${var.instance_prefix}-lnet2"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  config_drive = true
  network {
    uuid = "${openstack_networking_network_v2.net1.id}"
  }
  network {
    uuid = "${openstack_networking_network_v2.net2.id}"
  }
}


# --- net 3 ---
resource "openstack_networking_network_v2" "net3" {
  name           = "net3"
  admin_state_up = "true"
}
resource "openstack_networking_subnet_v2" "net3" {
  name            = "net3"
  network_id      = "${openstack_networking_network_v2.net3.id}"
  cidr            = "192.168.43.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"] #["131.111.8.42, 131.111.12.20]
  ip_version      = 4
}
resource "openstack_networking_router_interface_v2" "net3" {
  router_id = "${openstack_networking_router_v2.external.id}"
  subnet_id = "${openstack_networking_subnet_v2.net3.id}"
}


resource "openstack_compute_instance_v2" "client3" {
  name = "${var.instance_prefix}-client3"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    uuid = "${openstack_networking_network_v2.net3.id}"
  }
}

resource "openstack_compute_instance_v2" "lnet3" {
  name = "${var.instance_prefix}-lnet3"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  config_drive = true
  network {
    uuid = "${openstack_networking_network_v2.net2.id}"
  }
  network {
    uuid = "${openstack_networking_network_v2.net3.id}"
  }
  user_data = "#!/usr/bin/bash\nsudo ip route add 192.168.41.0/24 via 192.168.42.1"
}


# --- lustre server ---
resource "openstack_compute_instance_v2" "lustre_server" {
  name = "${var.instance_prefix}-storage"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    uuid = "${openstack_networking_network_v2.net1.id}"
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = var.floatingip_pool
}
resource "openstack_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = "${openstack_networking_floatingip_v2.fip_1.address}"
  instance_id = "${openstack_compute_instance_v2.lustre_server.id}"
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

# --- files ---
data  "template_file" "ohpc" {
    template = "${file("${path.module}/inventory.tpl")}"
    vars = {
      storage = <<EOT
${openstack_compute_instance_v2.lustre_server.name} ansible_host=${openstack_compute_instance_v2.lustre_server.network[0].fixed_ip_v4}
EOT
      net1 = <<EOT
${openstack_compute_instance_v2.client1.name} ansible_host=${openstack_compute_instance_v2.client1.network[0].fixed_ip_v4}
EOT
      lnet2 = <<EOT
${openstack_compute_instance_v2.lnet2.name} ansible_host=${openstack_compute_instance_v2.lnet2.network[0].fixed_ip_v4} eth1_address=${openstack_compute_instance_v2.lnet2.network[1].fixed_ip_v4}
EOT
      net2 = <<EOT
${openstack_compute_instance_v2.client2.name} ansible_host=${openstack_compute_instance_v2.client2.network[0].fixed_ip_v4}
EOT
      lnet3 = <<EOT
${openstack_compute_instance_v2.lnet3.name} ansible_host=${openstack_compute_instance_v2.lnet3.network[0].fixed_ip_v4} eth1_address=${openstack_compute_instance_v2.lnet3.network[1].fixed_ip_v4}
EOT
      net3 = <<EOT
${openstack_compute_instance_v2.client3.name} ansible_host=${openstack_compute_instance_v2.client3.network[0].fixed_ip_v4}
EOT
      fip_net1 = "${openstack_networking_floatingip_v2.fip_1.address}"
      ssh_user_name = "${var.ssh_user_name}"
      va_mgs = "${openstack_compute_volume_attach_v2.va_mgs.device}"
      va_mdt1 = "${openstack_compute_volume_attach_v2.va_mdt1.device}"
      va_ost1 = "${openstack_compute_volume_attach_v2.va_ost1.device}"
    }
    depends_on = [openstack_compute_instance_v2.client1]
}

resource "local_file" "hosts" {
  content  = "${data.template_file.ohpc.rendered}"
  filename = "${path.cwd}/ansible_inventory"
}
