output "public_ip" {
  value = openstack_networking_floatingip_v2.fip_1.address
  description = "Public IP for OpenHPC login node"
}

output "login_id" {
  value = openstack_compute_instance_v2.login.id
  description = "instance_id for the login node"
}
