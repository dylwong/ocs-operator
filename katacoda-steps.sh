#!/bin/bash

export REGISTRY_NAMESPACE=mulbc
export IMAGE_TAG=katacoda


cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-storage
spec: {}
---
apiVersion: v1
kind: Namespace
metadata:
  name: local-storage
spec: {}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  serviceAccount:
    metadata:
      creationTimestamp: null
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: local-operator-group
  namespace: local-storage
spec:
  serviceAccount:
    metadata:
      creationTimestamp: null
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: local-storage-manifests
  namespace: openshift-marketplace
spec:
  description: An operator to manage local volumes
  displayName: Local Storage Operator
  icon:
    base64data: ""
    mediatype: ""
  image: quay.io/gnufied/local-registry:v4.2.0
  publisher: Red Hat
  sourceType: grpc
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ocs-catalogsource
  namespace: openshift-marketplace
spec:
  displayName: Openshift Container Storage
  icon:
    base64data: ""
    mediatype: ""
  image: quay.io/$REGISTRY_NAMESPACE/ocs-registry:$IMAGE_TAG
  publisher: Red Hat
  sourceType: grpc
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-subscription
  namespace: openshift-storage
spec:
  channel: alpha
  name: ocs-operator
  source: ocs-catalogsource
  sourceNamespace: openshift-marketplace
EOF

oc edit csv
# --> Change ocs-operator image to quay.io/mulbc/ocs-operator:katacoda

oc project openshift-storage
watch oc get po,csv

seq 20 30 | xargs -n1 -P0 -t -I {} oc patch pv/pv00{} -p '{"metadata":{"annotations":{"volume.beta.kubernetes.io/storage-class": "localstorage-ocs-storageclass"}}}'
oc label "$(oc get no -o name | head -n1)" cluster.ocs.openshift.io/openshift-storage=""
oc label "$(oc get no -o name | head -n1)" topology.rook.io/rack=rack0

cat <<EOF | oc apply -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  namespace: openshift-storage
  name: ocs-storagecluster
spec:
  manageNodes: false
  monPVCTemplate:
    spec:
      storageClassName: thin
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi
  storageDeviceSets:
  - name: example-deviceset
    count: 1
    replica: 1
    resources: {}
    placement: {}
    dataPVCTemplate:
      spec:
        storageClassName: thin
        accessModes:
        - ReadWriteOnce
        volumeMode: Block
        resources:
          requests:
            storage: 100Gi
    portable: true
EOF

watch oc get po,pvc

# Toolbox
curl -s https://raw.githubusercontent.com/rook/rook/release-1.1/cluster/examples/kubernetes/ceph/toolbox.yaml | sed 's/namespace: rook-ceph/namespace: openshift-storage/g'| oc apply -f -
