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
  - [Readarr - Books](https://wiki.servarr.com/readarr)
  - [Whisparr - XXX](https://wiki.servarr.com/whisparr)
  - [Prowlarr - Indexer](https://wiki.servarr.com/prowlarr)
  - [Deluge - Data transfer](https://docs.linuxserver.io/images/docker-deluge/#version-tags)*
- [NGINX](https://nginx.org/en/docs/), in 3 configurations:
  - Edge load balancer, on my OPNsense firewall
  - Kubernetes ingress controller
  - Web site hosting

Each of these components will be built into a helm chart, and deployed using idempotent commands (possibly through a CICD pipeline 🤔)

# Deployment
Entrypoint for the deployment of the entire Burglarr stack.

If doing CICD deployment, please consider some cautionary points:
- I _strongly_ suggest writing your own deployment scripts.
  - I set `export KUBECONFIG=$HOME/.kube/config-bglr`

## Cluster
Cluster creation/deployment is described in [Cluster-Deployment.md](/docs/Cluster-Deployment.md).

### Configure Storage
The cluster will need Persistent Volumes, explained [here](https://github.com/benjaminpieplow/automation/blob/main/kubernetes/KUBERNETES.md#add-cluster-storage). Follow that verbatim, and the apps _should_ provision persistent storage as they need it, except for Plex (see Plex below).

## Sonarr
```
kubectl apply -f ./deploy/apps/sonarr/sonarr-manifest.yaml
```

## Plex
Plex will be by far the easiest, as they already provide a [Helm chart](https://github.com/plexinc/pms-docker/tree/master/charts/plex-media-server) which I can use. On the first deployment, you will need to generate your `plex_values.yaml`.

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

## Deluge
This might become [qBittorrent](https://github.com/linuxserver/docker-qbittorrent) as Deluge seems inactive, and I remember having to get creative with the Proxy forwarding to get the web UI working correctly.