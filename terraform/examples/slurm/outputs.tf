output "ophc_login_public_ip" {
  value = module.cluster.public_ip
  description = "Public IP for OpenHPC login node"
}
