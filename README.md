# ansible-lustre

Terraform/Ansible demonstration of multi-tenant Lustre.

# Overview

This repo creates and configures networks and nodes to represent the use of Lustre in a multi-tenent configuration:

```
network 1            network 2              network 3
 (tcp1)               (tcp2)                 (tcp3)
   |                    |                    |
   +-[lustre-storage]   |                    |
   +-[lustre-admin]     |                    |  
   +-[lustre-client1]   +-[lustre-client2]   +-[lustre-client2]
   |                    |                    |
   +---[lustre-lnet2]---+---[lustre-lnet3]---+
```

All networks are virtual but are intended to represent:
- tcp1: A low-latency storage network - any nodes on this are considered "trusted" in some sense
- tcp2: Ethernet
- tcp3: A project-specific software-defined network - nodes on this are untrusted
As well as being a virtual network, each network above is also a Lustre network (lnet).

The nodes on the networks are then:
- `lustre-storage`: The Lustre server, acting as MGS, MDT and OST. This exports a single fileystem `test_fs1`.
- `lustre-admin`: A Lustre client used to admininster the fileystem - it has a priviledged view of the real owners/permissions.
- `lustre-client[1-3]`: Lustre clients with different access levels to the filesystem (discussed below)
- `lustre-lnet[2-3]`: Lnet routers to provide connectivity between clients and server across the different networks.

The `test_fs` fileystem contains two "project directories":
    - `proj12`, which client 1 and 2 both have access to (with different permissions)
    - `proj3`, which only client 3 has access to

Various Lustre features are used to control how clients can access the project directories:
- lnet routes: These allow lustre traffic to cross network types, but also define define and hence control connectivity between clients and server.
- filesets: These restrict which subdirectories of the lustre filesystem clients can mount.
- nodemaps: These can be used to alter user's effective permissions, such as squashing root users to non-priviledged users.            
- shared keys: These can be used to prevent mounting of the filesystem unless client and server have appropriate keys,
               and/or to encrypt data in transit. Note this feature is not demonstrated here - see [Known Issues](#known-issues).

In addition to help prevent accidental configuration changes, tools are provided to export lustre configuration to a file with automatic diffing against
a previous known-good configuation if defined.

# Clients and Users

TODO:

# Usage
The below assumes deployment on `vss` from `ilab-gate`.

## Create infrastructure with terraform

[Download](https://www.terraform.io/downloads.html) the 0.12.x release, unzip and install it:

    export terraform_version="0.12.20"
    wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip
    unzip terraform_${terraform_version}_linux_amd64.zip

From Horizon download a clouds.yaml file and put it in:

    terraform/examples/slurm/clouds.yaml

Now use Terraform to create the infrastructure:

    cd terraform/examples/slurm
    terraform init
    terraform plan
    terraform apply

## Install Ansible and requirements

    cd ansible
    virtualenv .venv
    . .venv/bin/activate
    pip install -U pip
    pip install -U -r requirements.txt

## Install and configure Lustre and projects:
In the `ansible/` directory With the virtualenv activated as above, run:

    ansible-playbook main.yml -i inventory

Note that the inventory file is a symlink to the output of terraform.

Once this has completed, there will be Lustre configuration in `ansible/lustre-configs-live/`. To provide protection against misconfiguration, review these
for correctness and then copy (and potentially commit them) to `ansible/lustre-configs-good/`. Ansible will then compare live config against this each time it is run
and warn if there are differerences.

# Configuration
This section explains how the Lustre configuration is defined by this code.

## Definining nodes for roles
This is defined by the groups defined in the inventory template at `terraform/modules/cluster/inventory.tpl`. This is standard Ansible and is not discussed further here.

## Lnets and Lnet routes
These are defined by `ansible/group_vars`:
- `lnet_tcpX`: These define the *first* interface on each node, and hence the LNETs which exist. So all nodes (including routers), need to be added to the appropriate one of these groups.
- `lnet_router_tcpX_to_tcpY`: These define the 2nd interface for routers and also set the routing enabled flag. So only routers need to be added to these groups. Note that the convention here is that `eth0` goes on the lower-numbered network, and that this is the side ansible uses to configure router nodes.
- `lnet_tcpX_from_tcpY`: These define routes, so any nodes (clients, storage or routers) which need to access nodes on other networks need to be in one or more of these groups. In the routes `dict` in these groups there should be one entry, with the key defining the "end" network (matching the "X" in the filename) and a value defining the gateway. Note a dict is used with `hash_behaviour = merge` set in `ansible/ansible.cfg` so that nodes can be put in more than one routing group, and will end up with multiple entries in their `routes` var. In the example here this is needed for the storage server, which requires routes to both `tcp2` and `tcp3`.

These groups are then used to generate a configuration file for each node using the `ansible/lnet.conf.j2` template.

Additional general information about how lnet routes work is provided TODO: below.


## Nodemap parameters
Ansible generates one nodemap per client. Default values are provided by the `lustre` mapping in `ansible/group_vars/all` and overriden for specific client groups (e.g. `ansible/group_vars/client_net1.yml`) as required. The key/value pairs in this mapping function essentially as described in the Lustre nodemap [property documentation](http://doc.lustre.org/lustre_manual.xhtml#alteringproperties), with the exception that as a convenience user/group squashing is defined in terms of the user/group name to squash to, rather than the id (the id is then looked up from the `projects` mapping in the group_vars).

# Limitations
Once the cluster is running, changing Lustre configuration is slightly tricky and may require unmounting/remounting clients, or waiting for changes to propagate.

When run, the Ansible will enforce that:
- No nodemaps other than the ones it defines (and `default`) exist
- All parameters on those nodemaps match the Ansible configuration
However it does not enforce that:
- No additional clients (ranges) are present in the nodemaps it defines
- No additional routes exist
although both of these cases should be caught by the automatic diff of Lustre configuration against a known-good config, if defined.

# Known Issues and Limitations

- Terraform may need to be run twice due to errors like `"Network <id> requires a subnet in order to boot instances on."`
- If you see errors for any of the below Ansible actions just rerun the Ansible command:
  - Entropy
  - Installation of Lustre client kmods (possibly this is hitting repo rate limiting?)
  - `lnet-test.yml` (possibly server not ready?)
- Shared-key security (ssk) does not currently work due to
  - A bug in how Lustre handles `sudo` for ssk.
  - Reverse DNS lookups (required for ssk) not working in the VSS environement as configured here.
  Therefore at present `group_vars/all.yml:ssk_flavor` should be set to `'null'` to disable this.


# Lustre networks
There are essentially 3 aspects to be configured:
- All nodes must have an interface (e.g. eth0) on an Lnet (e.g. tcp1): Note that an Lnet itself is only actually defined by the set of nodes with an interface on it - there is no "stand-alone" definition of  an LNET.
- Routers also need an interface onto a 2nd Lnet, and a routing enabled flag set on.
- Nodes which need to be able to reach nodes on other networks need routes to be defined. Note that this includes any routers which need to route messages to networks they are not directly connected to.

A few aspects of routes may not be are not obvious:
- Routes need to be set up bi-directionally, and asymmetric routes are an advanced feature not recommended for normal use by the documentation.
- Routes are defined *for* a specific node, but *to* a whole network. This means that you can enable e.g. a client in net3 to reach storage in net1, without the reverse route enabling a client in net1 to access the client in net3 (because the reverse route is only defined for storage1).
- Routes are defined in terms of the "end" network and the gateway to access to get there. The gateway is the router which provides the "closest" hop towards the end network.
Multi-hop paths require routes to be defined along the way: e.g. if node "A" in network 1 needs to go through networks 2 and 3 to reach node "B" in network 4 then:
- node "A" needs a route to 4 to be defined using the gateway router from 1-2.
- The router forming the 1-2 gateway needs a route to 4 to be defined using a gateway from 2-3.
- The router forming the 2-3 gateway needs a route to 4 to be defined using a gateway from 3-4.
