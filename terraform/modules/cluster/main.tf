terraform {
  required_version = ">= 0.12, < 0.13"
}

resource "openstack_compute_keypair_v2" "terraform" {
  name       = "terraform_${var.instance_prefix}"
  public_key = "${file("${var.ssh_key_file}.pub")}"
}

resource "openstack_compute_instance_v2" "login" {
  name = "${var.instance_prefix}-login"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    name = "${var.network_name}"
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = "${var.floatingip_pool}"
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

data  "template_file" "ohpc" {
    template = "${file("${path.module}/inventory.tpl")}"
    vars = {
      login = <<EOT
${openstack_compute_instance_v2.login.name} ansible_host=${openstack_compute_instance_v2.login.network[0].fixed_ip_v4}
EOT
      computes = <<EOT
%{for compute in openstack_compute_instance_v2.compute}
${compute.name} ansible_host=${compute.network[0].fixed_ip_v4}%{ endfor }
EOT
      fip = "${openstack_networking_floatingip_v2.fip_1.address}"
	  ssh_user_name = "${var.ssh_user_name}"
    }
    depends_on = [openstack_compute_instance_v2.compute]
}

resource "local_file" "hosts" {
  content  = "${data.template_file.ohpc.rendered}"
  filename = "${path.cwd}/ansible_inventory"
}
