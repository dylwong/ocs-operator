#!/bin/bash

export OCS_IMAGE=quay.io/mulbc/ocs-operator
export REGISTRY_NAMESPACE=mulbc
export IMAGE_TAG=katacoda-46

oc label "$(oc get no -o name)" cluster.ocs.openshift.io/openshift-storage=''

oc create ns openshift-storage
# oc create ns local-storage
oc project openshift-storage

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ocs-catalogsource
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/$REGISTRY_NAMESPACE/ocs-operator-index:$IMAGE_TAG
  displayName: OpenShift Container Storage
  publisher: Red Hat
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

# LSO install
# cat <<EOF | oc create -f -
# apiVersion: operators.coreos.com/v1
# kind: OperatorGroup
# metadata:
#   name: local-storage-group
#   namespace: local-storage
# spec:
#   targetNamespaces:
#   - local-storage
# ---
# apiVersion: operators.coreos.com/v1alpha1
# kind: Subscription
# metadata:
#   name: local-storage-operator
#   namespace: local-storage
# spec:
#   channel: "4.2"
#   installPlanApproval: Automatic
#   name: local-storage-operator
#   source: redhat-operators
#   sourceNamespace: openshift-marketplace
#   startingCSV: local-storage-operator.4.2.23-202003090920
# EOF

echo "let operators settle in" && sleep 1m

cat <<EOF | oc create -f -
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: localblock
provisioner: kubernetes.io/no-provisioner
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-vdb
spec:
  capacity:
    storage: 100Gi
  volumeMode: Block
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: localblock
  local:
    path: /dev/vdb
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/os_id
          operator: In
          values:
          - rhcos
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-vdc
spec:
  capacity:
    storage: 100Gi
  volumeMode: Block
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: localblock
  local:
    path: /dev/vdc
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/os_id
          operator: In
          values:
          - rhcos
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-vdd
spec:
  capacity:
    storage: 100Gi
  volumeMode: Block
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: localblock
  local:
    path: /dev/vdd
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/os_id
          operator: In
          values:
          - rhcos
EOF

seq 20 30 | xargs -n1 -P0 -t -I {} oc patch pv/pv00{} -p '{"metadata":{"annotations":{"volume.beta.kubernetes.io/storage-class": "localfile"}}}'

cat <<EOF | oc create -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  manageNodes: false
  monPVCTemplate:
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 1
      storageClassName: localfile
      volumeMode: Filesystem
  storageDeviceSets:
  - count: 1
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1
        storageClassName: localblock
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 1
    resources: {}
EOF

curl -s https://raw.githubusercontent.com/rook/rook/release-1.1/cluster/examples/kubernetes/ceph/toolbox.yaml | sed 's/namespace: rook-ceph/namespace: openshift-storage/g' | oc apply -f -

watch oc -n openshift-storage get po,pvc

# Go into toolbox and execute:
# ceph osd lspools | cut -d ' ' -f2 | xargs -n1 -P3 -t -I {} ceph osd pool set {} size 1
