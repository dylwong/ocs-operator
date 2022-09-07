package collectors

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/red-hat-storage/ocs-operator/metrics/internal/options"
	cephv1 "github.com/rook/rook/pkg/apis/ceph.rook.io/v1"
	rookclient "github.com/rook/rook/pkg/client/clientset/versioned"
	cephv1listers "github.com/rook/rook/pkg/client/listers/ceph.rook.io/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/tools/cache"
	"k8s.io/klog"

	storagev1 "k8s.io/api/storage/v1"
	storagev1listers "k8s.io/client-go/listers/storage/v1"
)

type advancedFeatureType int

const (
	externalClusterMode advancedFeatureType = iota // 0
	pvEncryption                                   // 1
	kmsEncryption                                  // 2
	rbdMirror                                      // 3
	// add any advanced feature names above
	totalNoOfAdvFeatures // +1
)

type ClusterAdvanceFeatureCollector struct {
	AdvancedFeature   *prometheus.Desc
	Informer          cache.SharedIndexInformer
	AllowedNamespaces []string
	// advancedFeature will be set to
	// '1' if any of the cluster is using an advanced feature
	// or else it will be set to '0'.
	advancedFeature []int
}

const (
	// component within the project/exporter
	advFeatureSubSystem = "advanced_feature"
)

var _ prometheus.Collector = &ClusterAdvanceFeatureCollector{}

// NewClusterAdvancedFeatureCollector constructs the StorageCluster's advanced-feature collector
func NewClusterAdvancedFeatureCollector(opts *options.Options) *ClusterAdvanceFeatureCollector {
	client, err := rookclient.NewForConfig(opts.Kubeconfig)
	if err != nil {
		klog.Error(err)
		return nil
	}

	lw := cache.NewListWatchFromClient(client.CephV1().RESTClient(), "cephclusters", metav1.NamespaceAll, fields.Everything())
	sharedIndexInformer := cache.NewSharedIndexInformer(lw, &cephv1.CephCluster{}, 0, cache.Indexers{cache.NamespaceIndex: cache.MetaNamespaceIndexFunc})

	return &ClusterAdvanceFeatureCollector{
		AdvancedFeature: prometheus.NewDesc(
			prometheus.BuildFQName(namespace, advFeatureSubSystem, "usage"),
			`Indicates whether the cluster is using any advanced features, like PV/KMS encryption or external cluster mode`,
			nil, nil,
		),
		Informer:          sharedIndexInformer,
		AllowedNamespaces: opts.AllowedNamespaces,
		advancedFeature:   make([]int, totalNoOfAdvFeatures),
	}
}

// Run starts CephObjectStore informer
func (c *ClusterAdvanceFeatureCollector) Run(stopCh <-chan struct{}) {
	go c.Informer.Run(stopCh)
}

// Describe implements prometheus.Collector interface
func (c *ClusterAdvanceFeatureCollector) Describe(ch chan<- *prometheus.Desc) {
	ds := []*prometheus.Desc{
		c.AdvancedFeature,
	}

	for _, d := range ds {
		ch <- d
	}
}

// Collect implements prometheus.Collector interface
func (c *ClusterAdvanceFeatureCollector) Collect(ch chan<- prometheus.Metric) {
	cephClusterLister := cephv1listers.NewCephClusterLister(c.Informer.GetIndexer())
	cephClusters := getAllCephClusters(cephClusterLister, c.AllowedNamespaces)
	if len(cephClusters) > 0 {
		c.mapAdvanceFeatureUseFromCephClusters(cephClusters)
	}

	cephObjectStoreLister := cephv1listers.NewCephObjectStoreLister(c.Informer.GetIndexer())
	cephObjectStores := getAllObjectStores(cephObjectStoreLister, c.AllowedNamespaces)
	if len(cephObjectStores) > 0 {
		c.mapAdvanceFeatureUseFromCephObjectStores(cephObjectStores)
	}

	storageClassLister := storagev1listers.NewStorageClassLister(c.Informer.GetIndexer())
	storageClasses := getAllStorageClasses(storageClassLister, c.AllowedNamespaces)
	if len(storageClasses) > 0 {
		c.mapAdvanceFeatureUseFromStorageClasses(storageClasses)
	}

	cephRBDMirrorLister := cephv1listers.NewCephRBDMirrorLister(c.Informer.GetIndexer())
	cephRBDMirrors := getAllRBDMirrors(cephRBDMirrorLister, c.AllowedNamespaces)
	if len(cephRBDMirrors) > 0 {
		c.mapAdvanceFeatureUseFromCephRBDMirrors(cephRBDMirrors)
	}

	c.collectAdvancedFeatureUse(ch)
}

func (c *ClusterAdvanceFeatureCollector) mapAdvanceFeatureUseFromCephClusters(cephClusters []*cephv1.CephCluster) {
	for _, cephCluster := range cephClusters {
		if cephCluster.Spec.External.Enable {
			c.advancedFeature[externalClusterMode] = 1
			break
		} else if cephCluster.Spec.Security.KeyManagementService.IsEnabled() {
			c.advancedFeature[kmsEncryption] = 1
			break
		}
	}
}

func (c *ClusterAdvanceFeatureCollector) mapAdvanceFeatureUseFromCephObjectStores(cephObjectStores []*cephv1.CephObjectStore) {
	for _, cephObjectStore := range cephObjectStores {
		if cephObjectStore.Spec.Security.KeyManagementService.IsEnabled() {
			c.advancedFeature[kmsEncryption] = 1
			break
		}
	}
}

func (c *ClusterAdvanceFeatureCollector) mapAdvanceFeatureUseFromStorageClasses(storageClasses []*storagev1.StorageClass) {
	for _, storageClass := range storageClasses {
		if storageClass.Parameters["encrypted"] == "true" {
			c.advancedFeature[pvEncryption] = 1
			break
		}
	}
}

func (c *ClusterAdvanceFeatureCollector) mapAdvanceFeatureUseFromCephRBDMirrors(cephRBDMirrors []*cephv1.CephRBDMirror) {
	for _, rbdM := range cephRBDMirrors {
		if rbdM.Spec.Count > 0 {
			c.advancedFeature[rbdMirror] = 1
			break
		}
	}
}

func (c *ClusterAdvanceFeatureCollector) collectAdvancedFeatureUse(ch chan<- prometheus.Metric) {
	advFeature := 0
	for _, v := range c.advancedFeature {
		advFeature += v
	}
	if advFeature > 0 {
		advFeature = 1
	}
	ch <- prometheus.MustNewConstMetric(
		c.AdvancedFeature,
		prometheus.GaugeValue, float64(advFeature),
	)
}

func getAllStorageClasses(
	lister storagev1listers.StorageClassLister,
	namespaces []string) []*storagev1.StorageClass {
	var err error
	allSCs, err := lister.List(labels.Everything())
	if err != nil {
		klog.Errorf("couldn't list StorageClasses. %v", err)
		return nil
	}
	if len(namespaces) == 0 {
		return allSCs
	}
	var namespacedSCs []*storagev1.StorageClass
	for _, namespace := range namespaces {
		for _, eachSC := range allSCs {
			if eachSC.Namespace == namespace {
				namespacedSCs = append(namespacedSCs, eachSC)
			}
		}
	}
	return namespacedSCs
}

func getAllRBDMirrors(lister cephv1listers.CephRBDMirrorLister, namespaces []string) []*cephv1.CephRBDMirror {
	var err error
	allRBDMirrors, err := lister.List(labels.Everything())
	if err != nil {
		klog.Errorf("couldn't list RBD Mirrors. %v", err)
		return nil
	}
	if len(namespaces) == 0 {
		return allRBDMirrors
	}
	var namespacedRBDMirrors []*cephv1.CephRBDMirror
	for _, namespace := range namespaces {
		for _, eachRBDMirror := range allRBDMirrors {
			if eachRBDMirror.Namespace == namespace {
				namespacedRBDMirrors = append(namespacedRBDMirrors, eachRBDMirror)
			}
		}
	}
	return namespacedRBDMirrors
}
