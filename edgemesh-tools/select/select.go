package main

import (
	"context"
	"flag"
	"fmt"
	"math/rand"
	"net"
	"time"

	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"

	"edgemesh-tools/util"
)

var kubeClient *kubernetes.Clientset

func init() {
	flag.Usage = usage
	kubeClient = util.GetKubeClient()
}

func doHandle(filterLabels string) {
	nodes, err := kubeClient.CoreV1().Nodes().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		// klog.Errorf("failed to get nodes, filter labels %s, err: %v", filterLabels, err)
		return
	}
	scheduleNode := nodes.Items[rand.Intn(len(nodes.Items))]
	var nodeIP string
	for _, address := range scheduleNode.Status.Addresses {
		if address.Type == v1.NodeInternalIP {
			nodeIP = address.Address
			if ip := net.ParseIP(nodeIP); ip != nil {
				fmt.Printf("%s,%s", scheduleNode.Name, nodeIP)
				break
			}
		}
	}
}

func usage() {
	fmt.Printf(`
            		edgemesh tools select

select will select one node from K8s cluster to run edgemesh-server,
and print nodeName, nodeIP after .

Usage:
  ./select --filter-labels key1=val1,key2=val2 (default: "")

`)
}

func main() {
	rand.Seed(time.Now().UnixNano())

	var filterLabels string

	flag.StringVar(&filterLabels, "filter-labels", "", "filter nodes by these labels")

	flag.Parse()

	doHandle(filterLabels)
}
