[all:vars]
ansible_user=${ssh_user_name}
ssh_proxy=${fip_net1}
ansible_ssh_common_args='-C -o ControlMaster=auto -o ControlPersist=60s -o ProxyCommand="ssh ${ssh_user_name}@${fip_net1} -W %h:%p"'
mgs=${va_mgs}
mdts='["${va_mdt1}"]'
osts='["${va_ost1}"]'
# FIXME: above lists need to be generated
[storage_net1]
${storage}

[client_net1]
${net1}

[router_net1_to_net2]
${lnet2}

[client_net2]
${net2}

[router_net2_to_net3]
${lnet3}

[client_net3]
${net3}

[lustre_server:children]
storage_net1

[lustre_client:children]
client_net1
client_net2
client_net3
router_net1_to_net2
router_net2_to_net3

[lnet_tcp1:children]
storage_net1
client_net1
router_net1_to_net2

[lnet_tcp2:children]
client_net2
router_net2_to_net3

[lnet_tcp3:children]
client_net3

[lnet_router_tcp1_to_tcp2:children]
router_net1_to_net2

[lnet_router_tcp2_to_tcp3:children]
router_net2_to_net3

# route definitions below here:
[lnet_tcp1_from_tcp2:children]
client_net2
router_net2_to_net3

[lnet_tcp3_from_tcp2:children]
router_net1_to_net2

[lnet_tcp2_from_tcp1:children]
storage_net1

[lnet_tcp2_from_tcp3:children]
client_net3

[lnet_tcp1_from_tcp3:children]
client_net3

[lnet_tcp3_from_tcp1:children]
storage_net1
