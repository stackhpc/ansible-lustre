data "openstack_networking_network_v2" "internet" {
  name = "${var.floatingip_pool}"
}
