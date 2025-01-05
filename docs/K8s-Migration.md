# Right, what's all this then?
This document details the migration of Burglarr from docker-compose onto Kubernetes. Sure, I could just run the thing in compose, the way it was written, but this is more fun 😁

The main problems that I am going to have to solve:
- K8s mounting SMB shares
- Migrate from containerd to cri-o
- Parameterize the containers so all the variables can be fed in


# Some History and Context
Originally, Burglarr was built as PMS (Piracy Management System) as a collection of docker containers loosely strewn around. This became problematic to update (and the name was tacky), so I collected them as Burglarr; a fat docker-compose file. This, again, had the advantage of being very tinker-friendly. The deluge instance could be isolated on its own VM and the Plex server run bare-metal to make use of every last part of the potato it was running on. Now, a few factors are driving these changes:

* Plex/*arr have stabilized and no longer need regular low-level troubleshooting
* I need to learn Kubernetes
* I am no longer a broke college student running decade-old asset disposal PCs; I have less time but more hardware

Migrating the Burglarr app into Kubernetes will tick all these boxes. Note: Before you jump to inform me that Kubernetes will take up more time than the docker-compose solution; I know, but maintaining the docker-compose solution _while_ learning Kubernetes will use more time than learning Kubernetes and not maintaining the docker-compose solution 😉


# K8s mounting SMB shares
The original Burglarr was built on a single host, and expected that the host had a mount with your media library. No doubt that worked - it was the only option at the time (well, the only option available to me and my capacity to care) but it wasn't K8s-friendly. One principal of Kubernetes is to split node from application configuration, and application data configuration fits squarely on the side of the application, not the node. However, this protocol remains widely used (in my network and others') so there are still systems which depend on it.


## Potential solutions
I'm in the habit from work; this is called an environmental analysis 🙃 TL;DR: We need both.

I don't know how I will handle Deluge's downloads yet, I've had problems with Deluge endlessly re-scanning the library while using SMB shares but don't want to sacrifice a few hundred GBs of precious cluster storage for files that could be served by a Raspberry Pi and a USB-2 HDD.

## rclone
Rclone markets itself as the file manager for Cloud. This solution is most likely to have the widest community support, especially examples and troubleshooting posts, at the expense of possibly rug-pulling features (remember [bukkit](https://blog.jwf.io/2020/04/open-source-minecraft-bukkit-gpl/)?) without much warning.

[Plex](https://www.plex.tv/blog/plex-pro-week-23-a-z-on-k8s-for-plex-media-server/) says to use [rclone](https://rclone.org/);

> Rclone is a really powerful tool that can mount a ton of different storage platforms as volumes, so we didn’t need to specifically account for all the different data sources that one might want to use. A normal Rclone configuration file should be used, we would recommend using the `rclone config` command to create the file.

This [blog](https://blog.init-io.net/post/2024/kubernetes-rclone-mount/) suggests 3 ways to implement this. #1, the DaemonSet,

> The DaemonSet will execute the rclone mount command on every node of your Kubernetes cluster, so no matter on which node a pod starts, the mount will be there.

Absolutely would work, but this goes against the "abstract the application" doctrine I am following. Instead, #2 and #3 involve a Sidecar container,

> With the sidecar container you can mount the data only in this specific Pod by using an emptyDir volume.

~~Let's look at building this sidecar.~~ Plex provides this sidecar, it only has to be configured and enabled.

## csi-driver-smb
The [csi-driver-smb](https://github.com/kubernetes-csi/csi-driver-smb/blob/master/deploy/example/e2e_usage.md) specializes in using SMB shares in Kubernetes. It is maintained by the Kubernetes team, so is likely to have the least "diverging from the framework" bugs and long-term stability, at the cost of limited features. It would allow me to create PVs in my existing SMB file shares, but I find SMB to be needlessly complicated compared to a nice simple BLOB service (read: I suck at permissions). This means, I need to migrate my NAS onto TrueNAS Scale (which has been a long time coming anyway), so let's do that.

I just spent the weekend migrating to TrueNAS Scale for the minIO "App", only to realize, this is not in any way shape or form supported! I'm building my clusters on NFS, so I'll start there and figure out the SMB driver once I have presence in the cluster.

## Secrets
This addresses something my (current) cluster config does not provision: Secrets. In GitOps, you want your system's desired state described in code. However, this becomes problematic if that desired state defines logging into stuff. Docker-Burglarr solved this by handing file server auth over to the OS, which was just text files. Knowing Linux is always just text files all the way down, I'm not too concerned about using a fancy tool to harden this as suggested by plex; the host is a failure zone, as long as they aren't in GIT I'm happy.

[Kubernetes secrets](https://kubernetes.io/docs/concepts/configuration/secret/) should work for this; worst-case scenario I'll create one out-of-band and save it as a template. No VC, but you get what you pay for.
