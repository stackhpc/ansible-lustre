# ansible-lustre

Ansible to configure Lustre, with a terraform based example usage.

This creates and configures the following:

- 3x openstack networks (net1 - net3) with corresponding lustre networks (LNETs) (tcp1 - tcp3).
- A combined lustre management/storage server on net1/tcp1, a lustre client on each network, and lustre routers connecting them in a linear topology: tcp1---tcp2---tcp3.
- An OpenStack router both to provide access from a floating (external) IP and also to provide ansible with a way to contact all the nodes - this latter use is not representative of a production system.
- LNET routes to provide connectivity between all clients and the storage server.
- Tests for the above lnet connectivity

It also provides tools: see `lnet-export.py` and `parse-lnet.py`.

## Create infrastructure with terraform

Download the 0.12.x release and unzip it:
https://www.terraform.io/downloads.html

Install doing things like this:

    export terraform_version="0.12.20"
    wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip
    unzip terraform_${terraform_version}_linux_amd64.zip

From Horizon download a clouds.yaml file and put it in:

    terraform/examples/slurm/clouds.yaml

Now you can get Terraform to create the infrastructure:

    cd terraform/examples/slurm
    terraform init
    terraform plan
    terraform apply

## Install Lustre with Ansible

You may find this useful to run the ansible-playbook command below:

    cd ansible
    virtualenv .venv
    . .venv/bin/activate
    pip install -U pip
    pip install -U -r requirements.txt

You can create a cluster by doing:

    ansible-playbook main.yml -i inventory

Note that the inventory file is a symlink to the output of terraform.

## Rough edges

- Terraform may need to be run twice due to errors like `"Network <id> requires a subnet in order to boot instances on."`
- Ansible may need to be run twice due to errors installing lustre client kmods (possibly hitting repo rate limiting?)
- Have also seen `lnet-test.yml` playbook fail the first time then work (possibly server not ready)?
- Lustre configuration currently can't (easily) be changed once cluster built.

## Lustre networking info
There are essentially 3 aspects to be configured:
- All nodes must have an interface (e.g. eth0) on an LNET (e.g. tcp1): Note that an LNET itself is only actually defined by the set of nodes with an interface on it - there is no "stand-alone" definition of  an LNET.
- Routers also need an interface onto a 2nd LNET, and the routing enabled flag set on.
- Nodes which need to be able to reach nodes on other networks need routes to be defined. Note that this includes any routers which need to route messages to networks they are not directly connected to.

There are a few things which may not be obvious about routes:
- Routes need to be set up bi-directionally to work (TODO: check this!). They don't actually have to be symmetrical but asymmetric routes are an advanced/not recommended by default feature.
- Routes are defined *for* a specific node, but *to* a whole network. This means that you can enable e.g. a client in net3 to reach storage in net1, without the reverse route enabling a client in net1 to access the client in net3 (because the reverse route is only defined for storage1).
- Routes are defined in terms of the "end" network and the gateway to access to get there. The gateway is the router which provides the "closest" hop towards the end network.
Multi-hop paths require routes to be defined along the way: e.g. if node "A" in network 1 needs to go through networks 2 and 3 to reach node "B" in network 4 then:
- node "A" needs a route to 4 to be defined using the gateway router from 1-2.
- The router forming the 1-2 gateway needs a route to 4 to be defined using a gateway from 2-3.
- The router forming the 2-3 gateway needs a route to 4 to be defined using a gateway from 3-4.

In this code, all of the above configuration is defined in ansible by generating an `lnet.conf` file for each node. The content of this is potentially specific for each node, as it is determined by `group_vars` and hence by assigning nodes to groups in the inventory template `terraform/modules/cluster/inventory.tpl`. So the latter defines the network connectivity. The groups act as follows:
- `lnet_tcpX`: These define the *first* interface on each node, and hence the LNETs which exist. So all nodes, including routers, need to be added to the appropriate one of these groups.
- `lnet_router_tcpX_to_tcpY`: These define the 2nd interface for routers and also set the routing enabled flag. So only routers need to be added to these groups. Note that the convention here is that `eth0` goes on the lower-numbered network, and that this is the side ansible uses to configure router nodes.
- `lnet_tcpX_from_tcpY`: These define routes, so any nodes (clients, storage or routers) which need to access nodes on other networks need to be in one or more of these groups. In the routes `dict` in these groups there should be one entry, with the key defining the "end" network (matching the "X" in the filename) and a value defining the gateway. Note a dict is used with `hash_behaviour = merge` set in `ansible/ansible.cfg` so that nodes can be put in more than one routing group, and will end up with multiple entries in their `routes` var. In the example here this is needed for the storage server, which requires routes to both `tcp2` and `tcp3`.

# Mounted projects
- Define a list of project names in the `projects` vars in `group_vars/all`. For each project a user (with this name) and directory (with this name, owned by the user) in the lustre filesystem is created on the lustre server.
- For each client or client group requireing project access define a list `mounts` in `group_vars/client_net*/mounts.yml`. These will be mounted on the clients at `/mnt/lustre/<fs_name>/<project>/` **NB: may change!**.
TODO: add nodemapes and ssk for these.

# TODO:
- Swap inventory etc from `ansible_host` to `eth0_address`.
