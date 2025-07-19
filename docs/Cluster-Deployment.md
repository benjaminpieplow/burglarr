# Right, what's all this then?
This document outlines steps to get a Kubernetes cluster built for Burglarr. It is meant to be a dry configuration manual, paired with `K8s-Migration.md` which adds context.

![Cluster Diagram](cluster.drawio.svg)

# Cluster
I will be launching a new cluster for this project, as this Kubernetes deployment will likely need some customizations in the end. The cluster needs a few customizations:

- "VPN Subnet" the cluster will be on a special DMZ subnet configured to catch all non-local traffic and route it through a VPN tunnel
  - I have not modernized the setup instructions for this 😔
  - Firewall exemptions must be created for the cluster to reach the file server, and the edge proxy to reach the cluster
- GPU passthrough
  - The joke here, is the one I tell myself: I will update this documentation once I get it working.

## Cluster setup
Following my own [guide](https://github.com/benjaminpieplow/automation/wiki/New-K8s-Node-Cluster) (note: to automation README), things that had to be changed:
- I hard-coded the NIC VLAN into the template VM, which overrode the VLAN ID set by ansible; this had to be changed manually (and should probably be removed from the template)
- Since the FW will be sensitive, I statically set the IPs in OPNsense. DNS will still be used when looking up hosts, but the IPs won't wander.
- OPNsense -> Services -> Unbound DNS -> General -> Register DHCP Static Mappings must be set for static IPs to be registered. Obvious, if you know the setting is there!
- Ignore the "Storage" part, we will build that below.

## Storage
The setup guide guide describes creating a cluster Persistent Volume (PV) using NFS, which is horrendously insecure but extremely functional. The storage manifest (`/deploy/infra/storage.yaml`) deploys a new storage class specifically for your media collection, all other stores (_including downloads_) use automatically provisioned volumes from the clustter setup. This is covered in more detail in the Deployment section

## Network
I equipped each K8s host with an additional NIC attached to an air-gapped data network. This might be incorporated into future templates, as it's part of the standard SARCASM network structure, but for now it must be done manually.