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
- `lustre-storage`: The Lustre server, acting as MGS, MDT and OST. This exports a single fileystem `test_fs1`. It is given a public
                    IP and serves as a proxy for ssh access to nodes.
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

## Projects, Clients and Users

For demonstration purposes, the `test_fs` lustre fileystem contains two root directories, `/csd3` and `/srcp` and two "project directories":
- `/csd3/proj12` mounted by `client1` and `client2`
- `/srcp/proj3` mounted only by `client3`
Project directories are owned by a "project owner" user and group of the same name as the project, and given permissions `ug=rwx,+t`.

The Lustre configurations applied to the clients model different access scenarios:
- `client1` models a client on the CSD3 low-latency network which shares LDAP with the server and has full access to the filesystem (i.e. as controlled by normal Linux permissions), except that the client's root user is not privileged.
- `client2` models a client with access to the same project, but which does not share LDAP and has restricted access with the client's root user acting as the project owner.
- `client3` models a client in a isolated SRDP project, which does not share LDAP and has restricted access with a specific `datamanager` user acting as the project owner.

No LDAP service is actually provided here and all users are defined/configured by Ansible. The following demonstration users are set up to permit testing the above access control scenarios:
- `client1`: `andy` and `alex`
- `client2`: `becky` and `ben`
- `client3`: `catrin` and `charlie`

For details of how these aspects are configured, see [Configuration](configuration) below.

# Usage
The below assumes deployment on `vss` from `ilab-gate`.

**NB** There are some rough edges to this, see [Known Issues](#known-issues) if problems are encountered.

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

## Install and configure Lustre and projects
In the `ansible/` directory With the virtualenv activated as above, run:

    ansible-playbook -i inventory main.yml

Note that the inventory file is a symlink to the output of terraform.

Once this has completed, there will be Lustre configuration in `ansible/lustre-configs-live/`. To provide protection against misconfiguration, review these
for correctness and then copy (and potentially commit them) to `ansible/lustre-configs-good/`. Ansible will then compare live config against this each time it is run
and warn if there are differerences.

Optionally, monitoring may be then set up by running:

    ansible-playbook -i inventory monitoring.yml -e "grafana_password=<PASSWORD>"

where `<PASSWORD>` should be replaced with a password of your choice.

The `lustre-storage` node (see `ssh_proxy` in `inventory` for IP) then hosts Prometheus at port 9090 and Graphana (username="admin", password as chosen) at port 3000.

## Logging into nodes

To ssh into nodes use:

    ssh <ansible_ssh_common_args> centos@<private_ip>

where both `<ansible_ssh_common_args>` and the relevant `<private_ip>` are defined in `ansible/inventory`.

For routers, note the relevant IP is the one for the lower-numbered network it is connected to.

# Configuration
This section explains how the Lustre configuration described above is defined here.

## Roles for nodes
This is defined by the groups in the inventory template at `terraform/modules/cluster/inventory.tpl`.

## Lnets and Lnet routes
These are defined by `ansible/group_vars`:
- `lnet_tcpX`: These define the *first* interface on each node, and hence the lnets which exist. So all nodes (including routers), need to be added to the appropriate one of these groups.
- `lnet_router_tcpX_to_tcpY`: These define the 2nd interface for routers and also set the routing enabled flag. So only routers need to be added to these groups. Note that the convention here is that `eth0` goes on the lower-numbered network, and that this is the side ansible uses to configure router nodes.
- `lnet_tcpX_from_tcpY`: These define routes, so any nodes (clients, storage or routers) which need to access nodes on other networks need to be in one or more of these groups. In the routes `dict` in these groups there should be one entry, with the key defining the "end" network (matching the "X" in the filename) and a value defining the gateway. Note a dict is used with `hash_behaviour = merge` set in `ansible/ansible.cfg` so that nodes can be put in more than one routing group, and will end up with multiple entries in their `routes` var. In the example here this is needed for the storage server, which requires routes to both `tcp2` and `tcp3`.

These groups are then used to generate a configuration file for each node using the `ansible/lnet.conf.j2` template as part of the appropriate server/router/client role, and then imported to lustre.

Additional general information about how lnet routes work is provided under [Lustre networks](lustre-networks) below.

## Nodemaps
As client's can only be in one nodemap, a nodemap is generated for each client group (e.g. `client_net1` etc.). Nodemap parameters are set using the `lustre` mapping, with default values (which match Lustre's own defaults) given in `ansible/group_vars/all` overriden as required for specific client groups (e.g. in `ansible/group_vars/client_net1.yml`).

The key/value pairs in the `lustre` mapping function essentially as described in the Lustre [nodemap documentation](http://doc.lustre.org/lustre_manual.xhtml#lustrenodemap) to provide maximum flexibility. In brief:
- `trusted` determines whether client users can see the filesystem's canonical identifiers. Note these identifies are uid/gid - what user/group names these resolve (if at all) to depends on the users/groups present on the server.
- `admin` controls whether root is squashed. The user/group it is squashed to is defined by the `squash_uid` and `squash_gid` parameters.
- `squash_uid` and `squash_gid` define which user/group unmapped client users/groups are squashed to on the server. Note that although the lustre documentation states squashing is disabled by default, in fact (under 2.12 and 2.14 at least) the squashed uid and gid default to 99 (the `nobody` user). Therefore if squashing is not required the `trusted` property must be set.
- `deny_unknown` if set, prevents access to all users not defined in the nodemap.
- `fileset` if set, restricts the client to mounting only this subdirectory of the Lustre filesystem<sup id="foot1">[1](#f1)</sup>.
- `idmaps` define specific users/groups to map, contains a list where each item is a 3-list of:
    - mapping type 'uid' or 'gid'
    - client uid/gid to map to ...
    - ... uid/gid on server

This configuration follows Lustre's concepts/terminology very closely, although the use of Ansible makes it somewhat more user-friendly as for example uids can be looked up from usernames.

## Users
The demo users `andy` etc are defined for each client individually in `group_vars/client_net*.yml:users`. These users are created on the appropriate clients by `users.yml` which also creates the client1 users on the server to fake shared LDAP. While the lustre documentation specifically [states](http://doc.lustre.org/lustre_manual.xhtml#section_rh2_d4w_gk) that uid and gids are required to be the same "on all clients" this is not necessarily the case when clients are mounting isolated directories as here.

Note that `group_vars/all.yml` also defines `root` and `nobody` users - these are default OS users and are defined here purely to allow them to be referred to in the client nodemap setup. The combination of  `user` mappings from the `all` and client group_vars files requires having `hash_behaviour = merge` in ansible's configuration (as does the lnet configuration described above).

The project owner and project member user/groups are defined by `group_vars/all.yml:projects` and are also created by `users.yml`. For simplicity, these are the same on all clients and the server although strictly client2 does not need the `proj12` user/group, etc.

## Projects
Project directories are defined by `group_vars/all.yml:projects`. The `root` key is prepended to the project name to give the project's path in the lustre filesystem.

# Futher Discussion
This section provides extended context and discussion of configuration and behaviour.

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

## Project access

It is not necessarily obvious how to configure the nodemap functionality, project directory permissions and users/groups to give the desired access control. This section therefore provides narrative explanation of how the example configuration here actually works to provide the outcomes defined in [Projects and Users](#projects-and-users). If experimenting with configuration note that:
- While the manual says nodemap changes propagate in ~10 seconds, it was found necessary to unmount and remount the filesystem to get changes to apply, although this was nearly instantaneous and proved robust.
- Removal of idmaps etc will require manual intervention using lustre commands - see [Limitations](#limitations).
- Reducing the caching of user/group upcalls from the default 20 minutes to 1 second is recommended using:

        [centos@lustre-storage ~]$ sudo lctl set_param mdt.*.identity_expire=1

- Whether modifying configuration using ansible or lustre commands, running the `verify.yml` playbook and reviewing `ansible/lustre-configs-live/lustre-storage-nodenet.conf` is a convenient way to check the actual lustre configuration.

Firstly, note that the actual lustre fileystem configuration (defined in `group_vars/all/yml:projects`) is as follows:
- `/csd3/proj12`: owner=`proj12` group=`proj12` mode=`drwxrwx--T`
- `/srcp/proj3`: owner=`proj3` group=`proj3` mode=`drwxrwx--T`

This can be seen from the `admin` client which has both the `trusted` and `admin` properties set so its users (including `root`) can see the real filesystem ids.

Secondly, note that `users.yml` ensures the "project owner" users/groups (e.g. `proj12`) and "project member" user/groups (e.g. `proj12-member`) are present on both the server and clients 1-3:
- For the server and client1, this models LDAP as mentioned above.
- For the other clients these users/groups would have to be configured in some other way on both the client and the server, but uid/gids could differ between client and server.
- Users/groups do not necessarily need to be present on clients which do not mount the associated project directory (e.g. client3 does not need `proj12` and `proj12-member`) - this is done here purely to simplify the logic and configuration.
- `admin.yml` also ensures these users/groups are present on the `admin` client; this is not a lustre requirement but is done here because ansible uses user/group names rather than uid/gids when creating the project directories.

The client configurations are then as follows:

### Client 1
- As `fileset=/csd3` the client's `/mnt/lustre` provides access to any project directories within `/csd3`, e.g. `/mnt/lustre/proj12` -> `/csd/proj12`, but prevents access to projects in `/srcp`.

Considering access to `/csd3/proj12/`:
- Because `trusted=true` all client users see the true uid/gids in the filesystem hence permissions generally function as if it were a local directory given users/groups are present on both server and client.
- Client users `alex` and `andy` have a secondary group (on both server an client) of `proj12` hence get group permissions in the directory.
- As `admin=false` the `root` user is squashed to the default `squash_uid` and `squash_gid` of 99, i.e. user `nobody` and therefore has no permissions in the directory.
- The client user `centos` (not defined by `users.yml` but present on both client and server as a default OS user) does not have the correct secondary group and hence cannot access the directory.

### Client 2
- As `fileset=/csd3/proj12` the client's `/mnt/lustre` only provides access to this directory.
- Because `trusted=false` ALL users must be either defined in the `idmap` or will be subject to user/group squashing.
- The client's root user is mapped to `proj12` which gives it owner permissions in the project directory. It also means the project directory's owner to appears as `root` (rather than the real `proj12`) to all client users. Note the root group is *not* mapped as we want the project directory's group to appear as `proj12`.
- Users are squashed to `proj12-member` (i.e. a non-owning user) and groups to `proj12` (i.e. the directory's real group). Users therefore do not own the project directory but do match the directory's group.
- However to actually get the group permissions, client users (e.g. `becky` and `ben`) must also be members of the `proj12` group (on the client). It is not clear why this is necessary, given the group squashing. It is not necessary for the server user they are squashed to (`proj12-member`) to be a member of the appropriate group (`proj12`) on the server.
- The default OS user `centos` is not a member of `proj12` and hence has no access to the directory.

### Client 3
- As `fileset=/srcp/proj3` the client's `/mnt/lustre` only provides access to this directory.
- The nodemap and user configuration is exactly comparable to that for client 2, except that the client user `datamanager` (instead of `root`) is mapped to the project owner `proj3`. Note this user only exists on the client.
- Behaviour for demo users `cartrin` and `charlie` and the default OS user `centos` is exacly analogous to client 2.
- As `root` is not idmapped it is squashed to user `proj3-member` and group `proj3` as for all other users. However, unlike normal users it has group access without needing to have `proj3` as a secondary group..

# Limitations
As noted above changing Lustre configuration once the cluster is running may require manual intervention - consult the lustre documentation.

When run, the Ansible will enforce that:
- No nodemaps other than the ones it defines (and the `default` nodemap) exist
- All parameters on those nodemaps match the Ansible configuration

However it does not currently enforce that:
- No additional clients ("ranges") are present in the nodemaps it defines
- No additional routes exist
- No additional id mappings exist

Therefore these must be manually removed using lustre commands if required. However the `verify.yml` playbook can identify any of these issues if a known-good configuration is defined.

# Known Issues

- If you see any of the below errors from Ansible just rerun the Ansible command:
  - Authenticity of host cannot be established
  - Timeout waiting for priviledge escalation prompt
  - Failures during installation of Lustre client kmods (possibly this is hitting repo rate limiting?)
  - Failures of `lnet-test.yml` (possibly server not ready?) - obviously repeated failures are bad
- Shared-key security (ssk) does not currently work due to:
  - A bug in how Lustre handles `sudo` for ssk.
  - Reverse DNS lookups (required for ssk) not working in the VSS environment as configured here - fixing this is tricky due to the (OS) network setup.  
  Therefore at present `group_vars/all.yml:ssk_flavor` should be set to `'null'` to disable this.

- The "start lustre exporter" step of monitoring.yml sometimes gets stuck, can't work out why yet. Rerun the playbook (possibly several times) until past this.
- When running projects.yml, nodemap configuration parameters will always show as changed, even if they actually aren't. This is due to lustre CLI limitations.

# Potential next steps
Suggested routes for development are:
- Extend the export functionality provided by `tools/lustre-tools` to provide an `import` function which would "diff" the required state against the live state, make all necessary changes, and output the diff to allow ansible's `changed_when` to be accurate. This would fix the [limitations](#Limitations) in controlling lustre from ansible and the incorrect reporting of nodemap changes.
- In an environment where the reverse DNS lookup works correctly (i.e. `nslookup <ip_addr>` returns a name), work around the ssk sudo bug (e.g. by logging in as root when mounting) and test ssk functionality/performance. (Note current `authorized_keys` entries for `root` prevent running commands.)
- Add/use an `eth0_address` variable for hosts in addition to `ansible_host` to protect against unusual cases of the latter.
- Use [ganesha](https://github.com/nfs-ganesha/nfs-ganesha/wiki) running on the tenant router to re-export the lustre filesystem over NFS for the tenant's clients. This would remove the need for the clients to be running lustre.
- Update the lustre Prometheus exporter to use `https://github.com/HewlettPackard/lustre_exporter/pull/148` to provide OST data in 2.12 (note this PR currently doesn't compile).

---

<b id="f1">1.</b> The lustre documentation for the [Fileset Feature](http://doc.lustre.org/lustre_manual.xhtml#SystemConfigurationUtilities.fileset) is confusing/incorrect as it appears to be describing **submounts** which involve the client specifying a path in the filesystem, and are hence voluntary, with **filesets** where the client only specifies the filesystem to mount and the server only exports
the subdirectory defined by the appropriate fileset. Submount functionality is not exposed by this code. [↩](#foot1)