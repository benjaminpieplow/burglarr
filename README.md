# Right, what's all this then?
Burglarr is an implementation of my favorite tools to manage my media collection, made into an overcomplicated Kubernetes deployment so I could play with the technology. Notably, I created this with the goal of learning the Kubernetes framework, including services, networking, storage and deployment. I have tried to build/write this to be shareable, but the primary goal is to run _my_ Burglarr instance, so you may find some dependencies aren't outlined in documentation

Burglarr is broken down into 3 deployments, which create the following 8 pods:

![Service Diagram](docs/archi.drawio.svg)

- Media Distribution: [Plex media server](https://www.plex.tv/media-server-downloads/)
  - The HAMMER bootstrap script to optimize it for anime handling
  - I am temporarily out-scoping this; the Plex app has become unusable (eying Jellyfin) and the server needs _power_
- Media Managers: [The "arr" stack](https://wiki.servarr.com/) with Deluge and [Overseerr](https://overseerr.dev/)
  - [Sonarr - TV](https://wiki.servarr.com/sonarr)
  - [Radar - Movies](https://wiki.servarr.com/radarr)
  - [Lidar - Music](https://wiki.servarr.com/lidarr)
  - ~~[Readarr - Books](https://wiki.servarr.com/readarr)~~ Cancelled
  - ~~[Whisparr - XXX](https://wiki.servarr.com/whisparr)~~ My family sees this 🤦
  - [Prowlarr - Indexer](https://wiki.servarr.com/prowlarr)
  - [Ombi - Requests](https://docs.ombi.app/)
  - [Deluge - Data transfer](https://docs.linuxserver.io/images/docker-deluge/#version-tags)*
- [NGINX](https://nginx.org/en/docs/), in 3 configurations:
  - Edge load balancer, on my OPNsense firewall
  - Kubernetes ingress controller
  - Web site hosting

Each of these components will be built into a helm chart, and deployed using idempotent commands (possibly through a CICD pipeline 🤔)

# Deployment
Entrypoint for the deployment of the entire Burglarr stack. Read through this section sequentially, stop-and-fix problems.

If doing CICD deployment, please consider some cautionary points:
- I _strongly_ suggest writing your own deployment scripts for your lifecycles
  - I set `export KUBECONFIG=$HOME/.kube/config-bglr`
- I had to get creative with DNS, see below it's just for setup

The deployment happens in 3 phases.

1. Kubernetes
2. OOBE
3. Configuration

The **Kubernetes** involves deploying the cluster and associaetd resources. This is highly automated, and was the driving factor behind this project.

**OOBE** is mostly dealing with *arr specific things I could not automate; setting proxy base URLs. It's "10 minutes to do by hand, 10 weeks to automate".

**Configuration** is a mix of personalization, optimization and remaining config. It starts with (one thing) integrating the various services, then configuring profiles, integrations, etc.


## Cluster and supporting infra
Cluster creation/deployment is described in [Cluster-Deployment.md](/docs/Cluster-Deployment.md).

### Configure Config/Downloads Storage
The cluster will need Persistent Volumes, explained [here](https://github.com/benjaminpieplow/automation/blob/main/kubernetes/KUBERNETES.md#add-cluster-storage). Follow that verbatim, and the deployments _should_ auto provision persistent storage for all the services'. Each app needs a `/config` directory, and many use the `/downloads` mount (also created using the cluster storage infra). Each service's storage configuration is split into different manifests:

`deploy/infra/shared-storage.yaml` defines `downloads` and `media`, which should more-or-less lifecycle itself with the deployment (IE, if you nuke an app, they should persist). **This file must be customized and deployed before proceeding!** The `path` should line up with the base media folder (so, `/data/media/tv`, `path: /data/media`). Media Share file structure is covered below.

Once you have entered your media server and path, deploy the shared storage to the cluster:

```
kubectl apply -f ./deploy/infra/shared-storage.yaml
```
You can now skip to **Configure Media Storage**; the rest of this section is theory.

Kubernetes has the ability to "overdefine" shared resources (two deployments of the same object cause no issues); I could have added a `downloads` PV/PVC to each App manifest, but this comes with the trade-off that if you `kubectl delete` the app, the storage goes with it, which is "not very cash money" when you just want to restart a pod. For this reason, I split the app config from the rest of the workload.

`deploy/apps/*arr/*arr-storage.yaml` defines the Persistent Volume Claims for the apps' configuration. If an app has to be rebuilt (database corruption, forgot password) this can be included in the `kubectl delete`.

`deploy/apps/*arr/*arr-manifest.yaml` defines the Volumes for the app. If an app has to be redeployed (update, restart) a `kubectl delete` can be run against this manifest, without forcing a complete rebuild.

### Configure Media Storage
Your media library must also be shared, and was configured in `/deploy/infra/storage.yaml` (I will port to helm eventually). This section describes how the share must be configured, or at least how I got it working.

A user with UID=1000 must have full control of the media collection, I implemented this with an NFS-MapAll user (so as not to reset the permissions on the share).

The file structure must look like this:
```
media/
├─ ebooks/
├─ movies/
├─ music/
├─ tv/
```

Inside of that, the *arr service can _usually_ figure stuff out. Eventually, I will add support for more instances and expand `movies_4k` and `tv_fhd`; let's get it booting first.


### Configure DNS
The *arr stack OOBEs very nicely, but it's [not possible](https://github.com/linuxserver/docker-sonarr/issues/118) to sideload reverse proxy configuration. This means it's impossible to configure the services if they're hidden behind a single-hostname proxy, so the initial setup _must_ be done by identifying the service in the FQDN, not URL (`sonar.foo.com` vs `foo.com/sonarr`). The easiest workaround I have found to this, is to give each service an Ingress of `*arr.burglarr.local`. These are baked into the deployment, as you will _probably_ have to tweak stuff "in the backend" every once in a while (read: reconfigure a service from scratch)

Ideally, set a wildcard `*.burglarr.local` pointing to any node on your K8s cluster in your DNS. Since most clients don't support that (eg. the [Windows host file](https://superuser.com/questions/135595/using-wildcards-in-names-in-windows-hosts-file)), you will need to manually set each one as :
- sonarr.burglarr.local
- radarr.burglarr.local
- lidarr.burglarr.local
- prowlarr.burglarr.local
- deluge.burglarr.local
- jellyfin.burglarr.local
- ombi.burglarr.local


## Apps
Each of the apps can be deployed "in one go", but I recommend doing them one at a time so errors can be addressed before they're repeated.

There is exactly one (other, besides storage) hard-coded setting that I was not able to massage into a dynamic.

`deploy/apps/nginx/nginx-manifest.yaml` -> Ingress -> Host: Set this to the FQDN used for incoming requests, as they are set by the downstream proxy. I use OPNSense's NGINX, and they they [don't support](https://github.com/opnsense/plugins/issues/4396) rewriting this field, so ~~I~~ you have to adapt upstream to it. Once that is set, you are ready to deploy the stack:
```
kubectl apply -f ./deploy/apps/sonarr/
kubectl apply -f ./deploy/apps/radarr/
kubectl apply -f ./deploy/apps/lidarr/
kubectl apply -f ./deploy/apps/prowlarr/
kubectl apply -f ./deploy/apps/deluge/
kubectl apply -f ./deploy/apps/jellyfin/
kubectl apply -f ./deploy/apps/ombi/
kubectl apply -f ./deploy/apps/nginx/
```

Now, we have to do app-specific configuratiton and pipe them all together. I have tried to make this as efficient/painless as possible.

### OOBE/Set proxy forward addresses
Much of the integraiton config relies on the URLs, so this has to get done first. If your DNS magic worked and you used my K8s template, the apps should be available at http://APP.burglarr.local:31080/ so I will add those links.

For each app,
- set a password
- record API key in scratch notepad
- set base URL: Settings > General > URL Base: `/sonarr` (or whichever app you're in):
  - sonarr - http://sonarr.burglarr.local:31080/
  - radarr - http://radarr.burglarr.local:31080/
  - lidarr - http://lidarr.burglarr.local:31080/
  - prowlarr - http://prowlarr.burglarr.local:31080/
  - jellyfin - http://prowlarr.burglarr.local:31080/
    - Skip OOBE, bee-line the baseurl
    - The pod _may_ need a restart after this (or it needs a _hot_ minute), it took a few tries
    - NGINX may also need some restarting
    - Generate an API key, name "ombi" (not parsed)
  - ombi - http://prowlarr.burglarr.local:31080/ombi
    - Follow OOBE
    - OOBE jellyfin integration does not work
    - baseurl set by environment variable
    - add libraries now, so import can get to work
  - deluge - http://deluge.burglarr.local:31080/deluge
    - set strong password (no API keys in Deluge), default is `deluge`
    - install Labels plugin (stats recommended) -> this completes Deluge config
    - baseurl done by HTTP header




### Prowlarr
Once the app is online,
- Link other services (note: use "APP-service" such as `sonarr-service` for host, and :80, see below)
  - download service (deluge)
  - apps (radarr, sonarr) lidarr appears broken
  - indexers (caution: some may distribute illegal material)
  - "Sync App Indexers" pushes the indexers to your *arr stack

When configuring links to other services, you can reference them by their K8s service name:

![sonar-service](./docs/prowlarr-service.png)

### *arr
For each (radarr, sonarr, lidarr) service,
- Configure media profiles
  - Episode naming
  - Profiles (if needed)
  - Download Client -> Deluge (deluge-service:80)
    - Radarr: do not use URLbase
- Configure your library folders
- Begin the tedious process of cleaning up your library

### Jellyfin
- Add libraries and scan

# Legacy components
Please ignore; this is just for archive

## Plex 
~~Plex will be by far the easiest, as they already provide a [Helm chart](https://github.com/plexinc/pms-docker/tree/master/charts/plex-media-server) which I can use. On the first deployment, you will need to generate your `plex_values.yaml`.~~ dead wrong.

```
helm repo add plex https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages

helm show values plex/plex-media-server > plex_values.yaml
```


# Components
An in-depth analysis of the configurations and tweaks made for the deployment.

## Plex
### Nodeport or ClusterIP

Solution: Use ClusterIP, expose as service

According to the `values.yaml`,
```
  type: ClusterIP
  port: 32400

  # Port to use when type of service is "NodePort" (32400 by default)
  # nodePort: 32400

  # when NodePort is used, plex is unable to determine user IP
  # all traffic seems to come from within the cluster
  # setting this to 'Local' will allow Plex to determine the actual IP of user.
  # used to determine bitrate for remote transcoding
  # but the pods can only be accessed by the Node IP where the pod is running
  # Read more here: https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/#preserving-the-client-source-ip
  # https://access.redhat.com/solutions/7028639
  # externalTrafficPolicy: Local
```

Consider that in our deployment, we will be using an edge load balancer which expects the Kubernetes cluster's ingress controller to present all services on one port:

![Ingress](/docs/ingress.drawio.svg)

When the LB edge proxy (OPNsense) processes the request, it will rebuild the HTTP header and thus the underlying IP header. As such, preserving the client IP will do us no good. OPNsense's NGINX sets [X-Forwarded-For](https://github.com/opnsense/plugins/blob/master/www/nginx/src/opnsense/service/templates/OPNsense/Nginx/location.conf#L167), however [plex ignores this](https://www.reddit.com/r/PleX/comments/edxkh0/plex_not_respecting_xforwardedfor_or_xrealip/) (or did 5 years ago). Furthermore, "used to determine bitrate for remote transcoding" is not a great sell; one of my biggest gripes with Plex was having to instruct my clients to manually select a higher bitrate, as Plex always chose Potato quality when enough bandwidth was available to skip transcoding altogether. I may fix this in a future release, for now, I couldn't care less.

## Deluge (legacy)
This might become [qBittorrent](https://github.com/linuxserver/docker-qbittorrent) as Deluge seems inactive, and I remember having to get creative with the Proxy forwarding to get the web UI working correctly. The client itself was wonderful, offering a fat client and some sneaky redirects so you could open torrent files locally and have them forwarded to the "server".