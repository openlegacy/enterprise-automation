# Offline Hub Enterprise installation script

## Single-server installation

The installation script is supported for RH/Fedora and Debian distributions and was tested on **CentOS 7** and **Ubuntu 20.04**.
On other operating systems occasional errors may occur.

Make sure you have gathered all the information needed for the installation beforehand.
Here's the list:

#### DATABASE

- Postgres host. _Default: "postgres"_
- Postgres name. _Default: "postgres"_
- Postgres port. _Default: "5432"_
- Postgres username. _Default: "postgres"_

- Postgres password: _Default: "postgres"_
- Postgres admin password: _Default: "postgres"_

#### HUB ENTERPRISE

- URL which will be used to access the OpenLegacy Hub Web UI (e.g. 10.10.0.10).

In clean CentOS installation few packages are going to be **missing**. Run the following to prepare for the OL Hub installation:

Unzip
```
sudo yum install -y unzip
```

Docker
```
sudo yum install -y docker
```

**Important**. To run script not as root and to run docker not as root, you need to add a user you're going to use for
the installation to the docker group.
```
sudo groupadd docker
sudo usermod -aG docker centos
```

Docker Compose Plugin
```
sudo yum install -y docker-compose-plugin
```

Alternatively, you can install Docker Compose Plugin using curl:
```
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.24.1/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
```

If following packages are not installed/updated - postgres container won't start
```
sudo yum install -y runc
sudo yum update libseccomp
```

Download the bundle:
```
curl "https://bucket-for-download-portal.s3.eu-central-1.amazonaws.com/hub-ent-installation/3.0.6/hub-ent-offline-installer-wo-docker-images.zip" -o /opt/openlegacy/hub-ent-offline-installer.zip
```

If you want to run the script not as root, make sure your user has all necessary permissions set:
```
sudo mkdir /opt/openlegacy
sudo chown -R centos:centos /opt/openlegacy
```

Unzip its contents to `/opt/openlegacy`:
```
unzip /opt/openlegacy/hub-ent-offline-installer.zip -d /opt/openlegacy
```

Run the script:
```
/opt/openlegacy/installer-docker.sh
```

Run the script in non-interactive mode:

> **_NOTE:_** Before running the script for installation in non-interactive mode, need to cretate `installer-docker.conf` file from `installer-docker.conf.sample` file in the folder where script located and define required values, then run the script and wait untill isntallation complete.
```
/opt/openlegacy/installer-docker.sh
```

## Single-server upgrading

Install jq
```
sudo yum install -y jq
```
Download the upgrade bundle:
```
curl "https://bucket-for-download-portal.s3.eu-central-1.amazonaws.com/hub-ent-installation/prod/**NEW_VERSION**/hub-ent-offline-installer.zip" -o /opt/openlegacy/hub-ent-offline-upgrade.zip
```
Unzip archive to separate folder
```
unzip /opt/openlegacy/hub-ent-offline-upgrade.zip -d /opt/openlegacy/upgrade
```
Run the script:
```
/opt/openlegacy/upgrade/upgrade-docker.sh
```

Run the script in non-interactive mode:

> **_NOTE:_** Before running the upgrade script in non-interactive mode, in the same place where script located, need to cretate `upgrade-docker.conf` file from `upgrade-docker.conf.sample` file with required values, then run the script.
```
/opt/openlegacy/upgrade-docker.sh
```

## k8s installation

### Prerequisites

For the OpenLegacy Hub k8s installation, you must have a k8s cluster and external Postgres database already provisioned.

Script needs to be run on a Linux node which has a correct kubeconfig, a local configured copy of kubectl and helm
installed.

The following k8s distributions are supported:
- Vanilla Kubernetes 1.18+ (EKS, AKS, on-premise k8s)
- RedHat OpenShift 4+

In case of vanilla k8s, make sure that one of the following ingress controllers are already installed in the cluster:
- nginx-ingress-controller
- contour ingress controller

Your kubernetes cluster should support dynamic volume provisioning. We will use PersistentVolumeClaim and the default
storage class will be used for provisioning.

Make sure you have gathered all the information needed for the installation beforehand.
Here's the list:

#### KUBERNETES

- Names and tags of docker images which are needed for the installation. Hub-enterprise docker images should be saved in
  your registry and k8s cluster should be able to pull from it. `hub-ent-offline-installer-helm-with-docker-images.zip`
  archive has pre-packaged docker images if you need to save them.
- Your registry's credentials.
- Ingress controller type (list of supported controllers is provided above).
- If you manage certificates for your ingress inside your kubernetes cluster (not applicable to OpenShift), name of the
  secret where certificate is stored will be needed. Also, the secret should be accessible from the namespace where it is
  planned to provision Hub Enterprise.
- Name of the namespace where Hub Enterprise is going to be installed (should be created beforehand).

#### DATABASE

- Postgres host. _Example: "hub-enterprise-postgres"_
- Postgres name. _Example: "postgres"_
- Postgres port. _Example: "5432"_
- Postgres username. _Example: "postgres"_
- Postgres password.

#### HUB ENTERPRISE

- URL which will be used to access the OpenLegacy Hub Web UI. _Example: https://hub-enterprise.eks-contour.hub.com_
- URL which will be used to access the Keycloak Web UI. _Example: https://keycloak.eks-contour.hub.com_


Download the bundle:
```
curl "https://bucket-for-download-portal.s3.eu-central-1.amazonaws.com/hub-ent-installation/prod/**HUB_VERSION**/hub-ent-offline-installer-helm.zip" -o /opt/openlegacy/hub-ent-offline-installer-helm.zip
```

Unzip its contents to `/opt/openlegacy`:
```
unzip /opt/openlegacy/hub-ent-offline-installer-helm.zip -d /opt/openlegacy
```

Run the script:
```
/opt/openlegacy/installer-helm.sh
```

Run the script in non-interactive mode:

> **_NOTE:_** Before running the script for installation to the kubernetes in non-interactive mode, need to cretate `installer-helm.conf` file from `installer-helm.conf.sample` file in the `/opt/openlegacy` folder with required values, then run the script and choose correct kubernetes context.
```
/opt/openlegacy/installer-helm.sh
```

#### RESTORE DOCKER IMAGES

When bundle with docker images was downloaded, images can be restored and pushed to docker registry with the following commands:

- Docker
```
docker login -u <username> -p <password> <registry>
docker load < <image archive>
docker images
docker tag <image id> <image tag>
docker push <image tag>
```
- Podman
```
podman login -u <username> -p <password> <registry>
podman load -i <image archive>
podman images
podman tag <image id> <image tag>
podman push <image tag>
```

## Upgrade HUB ENTERPRISE

Run the script:
```
/opt/openlegacy/upgrade-helm.sh
```

Run the script in non-interactive mode:

> **_NOTE:_** Before running the helm upgrade script in non-interactive mode, need to cretate `upgrade-helm.conf` file from `upgrade-helm.conf.sample` file with required values, then run the script and choose correct kubernetes context.

When upgrading a Kubernetes deployment that uses persistent volumes, it's important to consider the implications for data persistence and the potential downtime. This section outlines the steps for a smooth upgrade and informs you about expected downtime.

Steps for Upgrading
Backup Your Data: Before starting the upgrade process, ensure that you have a backup of your persistent data. This can be done using snapshot features provided by your storage solution or manual backup methods.
Downtime Considerations

Duration: The downtime duration primarily depends on the time it takes to scale down the existing deployment and bring up the new pods. This process typically takes a few minutes, but it can vary based on the size of your application and the speed of your Kubernetes cluster.

Data Availability: During the downtime, data on the persistent volumes will remain intact, but it won't be accessible since the application pods using the volumes will be scaled down.


```
/opt/openlegacy/upgrade-helm.sh
```

## Post-installation notes

It is recommended to change username/password pair for the keycloak service after the installation is completed.
