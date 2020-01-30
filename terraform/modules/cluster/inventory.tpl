[all:vars]
ansible_user=${ssh_user_name}
ssh_proxy=${fip_net1}
ansible_ssh_common_args='-C -o ControlMaster=auto -o ControlPersist=60s -o ProxyCommand="ssh ${ssh_user_name}@${fip_net1} -W %h:%p"'

[storage_net1]
${storage}

[client_net1]
${net1}

[router_net1_to_net2]
${lnet2}

[client_net2]
${net2}

[client_net2:vars]
ssh_proxy=${fip_net2}
ansible_ssh_common_args='-C -o ControlMaster=auto -o ControlPersist=60s -o ProxyCommand="ssh ${ssh_user_name}@${fip_net2} -W %h:%p"'


[lustre_server:children]
storage_net1

[lustre_client:children]
client_net1
client_net2
router_net1_to_net2


[lnet_tcp1:children]
storage_net1
client_net1
router_net1_to_net2

[lnet_tcp2:children]
client_net2

[lnet_router_tcp1_to_tcp2:children]
router_net1_to_net2

[lnet_tcp2_from_tcp1:children]
storage_net1

[lnet_tcp1_from_tcp2:children]
client_net2
