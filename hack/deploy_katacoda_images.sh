#!/bin/bash

export REGISTRY_NAMESPACE=mulbc
export IMAGE_TAG=katacoda
make ocs-operator
podman push quay.io/$REGISTRY_NAMESPACE/ocs-operator:$IMAGE_TAG

OCS_OPERATOR_IMAGE="quay.io/$REGISTRY_NAMESPACE/ocs-operator:$IMAGE_TAG"
sed -i "s|quay.io/ocs-dev/ocs-operator:latest|$OCS_OPERATOR_IMAGE" ./deploy/olm-catalog/ocs-operator/0.0.1/ocs-operator.v0.0.1.clusterserviceversion.yaml

make gen-latest-csv
make ocs-registry
podman push quay.io/$REGISTRY_NAMESPACE/ocs-registry:$IMAGE_TAG
