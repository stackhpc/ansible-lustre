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
- tcp1: A low-latency storage network - nodes on this are considered "trusted" in some sense
- tcp2: Ethernet
- tcp3: A project-specific software-defined network - nodes on this are untrusted

As well as being a virtual network, each network above is also a Lustre network (lnet).

The nodes on the networks are then:
- `lustre-storage`: The Lustre server, acting as MGS, MDT and OST. This exports a single fileystem `test_fs1`.
- `lustre-admin`: A Lustre client used to admininster the fileystem - it has a privileged view of the real owners/permissions.
- `lustre-client[1-3]`: Lustre clients with different access levels to the filesystem (discussed below)
- `lustre-lnet[2-3]`: Lnet routers to provide connectivity between clients and server across the different networks.

Various Lustre features are used to control how clients can access the filesystem:
- lnet routes: These allow lustre traffic to cross network types, but also define define and hence control connectivity between clients and server.
- filesets: These restrict which subdirectories of the lustre filesystem clients can mount.
- nodemaps: These can be used to alter user's effective permissions, such as squashing root users to non-privileged users.            
- shared keys: These can be used to prevent mounting of the filesystem unless client and server have appropriate keys,
               and/or to encrypt data in transit. Note this feature is not functional at present - see [Known Issues](#known-issues).

In addition this repo provides two extra tools to help prevent misconfiguration:
- `lnet-test.yml` runs `lnet ping` to check connectivity is present between clients and server, and is not present between clients in different lnets.
- `verify.yml` exports lustre configuration to files on the control host, then automatically diffs them against a previous known-good configuation (if available).

# Projects, Users and Permissions

For demonstration purposes, the `test_fs` lustre fileystem contains two "project directories":
- `proj12` mounted by `client1` and `client2`
- `proj3` mounted only by `client3`
Each of these directories is owned by a "project owner" user of the same name.

The Lustre configurations applied to the clients represent different access scenarios:
- `client1` is on the low-latency network, shares LDAP with the server and has full access to the filesystem (i.e. as defined by Linux permissions) except that the client's root user is not privileged.
- `client2` has access to the same project, but does not share LDAP and has restricted access with the client's root user acting as the project owner.
- `client3` is in an isolated project, does not share LDAP and has restricted access with a specific `datamanager` user acting as the project owner.

In addition, some example "project users" are set up to permit testing the above permission control:
- `client1`: `andy` and `alex`
- `client2`: `becky` and `ben`
- `client3`: `catrin` and `charlie`

For information on how to control this, see [Nodemaps](nodemaps) below.

For demonstration purposes, the three clients are set up as follows:

Client 1:
- Represents a "trusted" client on the low-latency network using the same LDAP as the server.
- Mounts the `proj12` subdirectory
- Users can see canonical filesystem uid/gids.
- Root is squashed to the "nobody" user, uid/gid=99.

Client 2:
- Represents a client with access to the low-latency network but no shared LDAP.
- Also mounts the `proj12` subdirectory.
- Users cannot see canonical filesystem uid/gids.
- Root is mapped to the project owner user.
- All other users are mapped to a "project member" user.

Client 3:
- Represents a client in an isolated project, with no shared LDAP.
- Mounts the `proj3` subdirectory.
- Users cannot see canonical filesystem uid/gids.
- Root is squashed to the "nobody" user, uid/gid=99.
- A non-root user "datamanager" is mapped to the project owner.
- All other users are mapped to a "project member" user.

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
    ansible-galaxy install -r requirements.yml

## Install and configure Lustre and projects:
In the `ansible/` directory With the virtualenv activated as above, run:

    ansible-playbook main.yml -i inventory

Note that the inventory file is a symlink to the output of terraform.

Once this has completed, there will be Lustre configuration in `ansible/lustre-configs-live/`. To provide protection against misconfiguration, review these
for correctness and then copy (and potentially commit them) to `ansible/lustre-configs-good/`. Ansible will then compare live config against this each time it is run
and warn if there are differerences.

## Logging into nodes

To ssh into nodes use:

    ssh <ansible_ssh_common_args> centos@<private_ip>

where both `<ansible_ssh_common_args>` and the relevant `<private_ip>` are defined `ansible/inventory`.

For routers, note the relevant IP is the one for the lower-numbered network it is connected to.

# Configuration
This section explains how the Lustre configuration described above is defined here.

## Roles for nodes
This is defined by the groups in the inventory template at `terraform/modules/cluster/inventory.tpl` and should be fairly obvious.

## Lnets and Lnet routes
These are defined by `ansible/group_vars`:
- `lnet_tcpX`: These define the *first* interface on each node, and hence the LNETs which exist. So all nodes (including routers), need to be added to the appropriate one of these groups.
- `lnet_router_tcpX_to_tcpY`: These define the 2nd interface for routers and also set the routing enabled flag. So only routers need to be added to these groups. Note that the convention here is that `eth0` goes on the lower-numbered network, and that this is the side ansible uses to configure router nodes.
- `lnet_tcpX_from_tcpY`: These define routes, so any nodes (clients, storage or routers) which need to access nodes on other networks need to be in one or more of these groups. In the routes `dict` in these groups there should be one entry, with the key defining the "end" network (matching the "X" in the filename) and a value defining the gateway. Note a dict is used with `hash_behaviour = merge` set in `ansible/ansible.cfg` so that nodes can be put in more than one routing group, and will end up with multiple entries in their `routes` var. In the example here this is needed for the storage server, which requires routes to both `tcp2` and `tcp3`.

These groups are then used to generate a configuration file for each node using the `ansible/lnet.conf.j2` template.

Additional general information about how lnet routes work is provided under [Lustre networks](lustre-networks) below.

## Nodemaps
One nodemap is generated per client. Default values are provided by the `lustre` mapping in `ansible/group_vars/all` and overriden for specific client groups (e.g. in `ansible/group_vars/client_net1.yml`) as required.

The key/value pairs in this mapping function essentially as described in the Lustre [nodemap documentation](http://doc.lustre.org/lustre_manual.xhtml#lustrenodemap) to provide maximum flexibility. In brief:
- `trusted` determines whether client users can see the filesystem's canonical identifiers. Note these identifies are uid/gid - what user/group names these resolve (if at all) to depends on the users/groups present on the server.
- `admin` controls whether root is squashed. The user/group it is squashed to is defined by the `squash_uid` and `squash_gid` parameters.
- `squash_uid` and `squash_gid` define which user/group unmapped client users/groups are squashed to on the server. Note that although the lustre documentation states squashing is disabled by default, in fact (under 2.12 and 2.14 at least) the squashed uid and gid default to 99 (the `nobody` user). Therefore if squashing is not required the `trusted` property must be set.
- `fileset` if set, restricts the client to mounting only this subdirectory of the Lustre filesystem<sup id="foot1">[1](#f1)</sup>.
- `idmaps` define specific users/groups to map, and contain a list where each item is a 3-list of:
    - mapping type: 'uid', 'gid' or 'both'
    - client uid/gid to map to ...
    - ... uid/gid on server

The nodemap property `deny_unknown` is not currently supported here as it only appears useful if uid/gid mappings were defined for all users, which seems difficult to maintain.

## Users
While the lustre documentation [states that](http://doc.lustre.org/lustre_manual.xhtml#section_rh2_d4w_gk) uid and gids should be the same on all clients this is not necessarily the case where clients are mounting isolated directories. Conversely which nids/gids exist where must be carefully considered in parallel with the mappings provided by the nodemaps to make sure that nids/gids attached to files in project directories make sense to clients.

Therefore:
- The admin client creates the project owner user/group defined in the `projects` group_var so that it can create project directories with the right owners/groups.
- All project clients also create these users/groups so that their view of project directories is correct.
- The example project users are added to the appropriate project groups.

# Limitations
Once the cluster is running, changing Lustre configuration is tricky and may require unmounting/remounting clients, or waiting for changes to propagate. Consult the lustre documentation.

When run, the Ansible will enforce that:
- No nodemaps other than the ones it defines (and the `default` nodemap) exist
- All parameters on those nodemaps match the Ansible configuration

However it does not currently enforce that:
- No additional clients ("ranges") are present in the nodemaps it defines
- No additional routes exist
although both of these cases should be caught by the automatic diff of Lustre configuration against a known-good config, if defined.

# Known Issues

- Terraform may need to be run twice due to errors like `"Network <id> requires a subnet in order to boot instances on."`
- If you see any of the below errors from Ansible just rerun the Ansible command:
  - Timeout waiting for priviledge escalation prompt
  - Installation of Lustre client kmods (possibly this is hitting repo rate limiting?)
  - `lnet-test.yml` (possibly server not ready?)
- Shared-key security (ssk) does not currently work due to
  - A bug in how Lustre handles `sudo` for ssk.
  - Reverse DNS lookups (required for ssk) not working in the VSS environement as configured here.
  - Removed key transfer code broken by refactor
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


---

<b id="f1">1.</b> The lustre documentation for the [Fileset Feature](http://doc.lustre.org/lustre_manual.xhtml#SystemConfigurationUtilities.fileset) is confusing/incorrect as it appears to be describing **submounts** which involve the client specifying a path in the filesystem, and are hence voluntary, with **filesets** where the client only specifies the filesystem to mount and the server only exports
the subdirectory defined by the appropriate fileset. Submount functionality is not exposed by this code. [↩](#foot1)