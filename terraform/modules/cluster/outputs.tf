output "public_ip" {
  value = openstack_networking_floatingip_v2.fip_1.address
  description = "Public IP for OpenHPC login node"
}
