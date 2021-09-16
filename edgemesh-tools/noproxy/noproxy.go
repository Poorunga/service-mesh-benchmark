package main

import (
	"context"
	"flag"
	"fmt"
	"strings"

	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/klog/v2"

	"edgemesh-tools/util"
)

var kubeClient *kubernetes.Clientset

func init() {
	flag.Usage = usage
	kubeClient = util.GetKubeClient()
}

func doHandle(namespaces []string) {
	for _, ns := range namespaces {
		err := checkNamespace(ns)
		if err != nil {
			klog.Warningf("check namespace err: %v, skip", err)
			continue
		}
		addLabel(ns)
	}
}

// addLable label the services in the specified namespaces,
// only processes services of type ClusterIP and is not headless.
func addLabel(namespace string) {
	services, err := kubeClient.CoreV1().Services(namespace).List(context.Background(), metav1.ListOptions{})
	if err != nil {
		klog.Errorf("get services in %s err: %v", namespace, err)
		return
	}

	for _, svc := range services.Items {
		// filter non-ClusterIP
		if svc.Spec.Type != v1.ServiceTypeClusterIP {
			continue
		}
		// filter headless service
		if svc.Spec.ClusterIP == "None" {
			continue
		}
		// check exists
		if _, exists := svc.Labels["noproxy"]; exists {
			continue
		}
		// label service
		svc.Labels["noproxy"] = "edgemesh"
		_, err := kubeClient.CoreV1().Services(namespace).Update(context.Background(), &svc, metav1.UpdateOptions{})
		if err != nil {
			klog.Errorf("%s add noproxy=edgemesh label err: %v, skip", svc.Name, err)
			continue
		}
		klog.Infof("%s add noproxy=edgemesh label", svc.Name)
	}
}

func checkNamespace(namespace string) error {
	_, err := kubeClient.CoreV1().Namespaces().Get(context.Background(), namespace, metav1.GetOptions{})
	if err != nil {
		return err
	}

	return nil
}

func usage() {
	fmt.Printf(`
                                	edgemesh tools noproxy

noproxy will automatically label the services in the specified namespaces with noproxy=edgemesh to
prevent traffic from being hijacked by edgemesh. noproxy only processes services of type ClusterIP
and is not headless.

Usage:
  ./noproxy --namespaces namespace1,namespace2 (default: default,)

`)
}

func main() {
	var namespaces string

	flag.StringVar(&namespaces, "namespaces", "default", "service in namespace will be labeled with noproxy")

	flag.Parse()

	doHandle(strings.Split(namespaces, ","))
}
