variable "image" {
  default = "CentOS7-1907"
}

variable "flavor" {
  default = "general.v1.tiny"
}

variable "ssh_key_file" {
  default = "~/.ssh/id_rsa"
}

variable "ssh_user_name" {
  default = "centos"
}

variable "floatingip_pool" {
  default = "internet"
}

variable "instance_prefix" {
  default = "lustre"
}
