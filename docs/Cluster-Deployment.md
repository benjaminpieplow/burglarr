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
The setup guide guide describes creating a cluster Persistent Volume (PV) using NFS, which is horrendously insecure and does not allow us to access existing files. As such, we will need to configure 2 types of storage: **Persistent Volumes** for the configuration files of the various services, and **Mounts** for the media collections.

### Persistent Volumes
Through this project, I have updated the K8s OOBE to create dynamic persistent volumes on NFS shares; this saves me the administrative overhead of writing this documentation. They will "just work"...

Except for Plex, which somehow managed to override the `Mapall User` set on the NAS, which did not happen in another similarly deployed workload. I have a user `3002` which I can grant the required rights on the NAS; it's hacky but it worked. I hate Linux file permissions. 

### Mounts
[Via](https://kubernetes.io/docs/concepts/storage/volumes/), these appear to be my options for getting my media library into Plex
- [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath-volume-types)
  - included as example in the helm chart (so likely how it's expected to be done)
  - 