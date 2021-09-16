package util

import (
	"os"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/klog"
)

const kubeConfigPath = "/root/.kube/config"

func GetKubeClient() *kubernetes.Clientset {
	kubeConfig, err := clientcmd.BuildConfigFromFlags("", kubeConfigPath)
	if err != nil {
		klog.Errorf("Failed to build config, err: %v", err)
		os.Exit(1)
	}
	kubeClient := kubernetes.NewForConfigOrDie(kubeConfig)

	return kubeClient
}
