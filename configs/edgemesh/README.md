# EdgeMesh app

Visit https://github.com/kubeedge/edgemesh for more information.

## Install

```
helm install edgemesh --namespace kubeedge \
    --set server.nodeName=<your node name> --set server.publicIP=<your node eip> \
    --set agent.subNet=<your service-cluster-ip-range> --set agent.listenInterface=<your container network interface> .
```

**Install examples:**
```
helm install edgemesh --namespace kubeedge \
    --set server.nodeName=k8s-node1 --set server.publicIP=119.8.211.54 \
    --set agent.subNet=10.96.0.0/12 --set agent.listenInterface=cni0 .
```

**TIPS:**

1.You can get your `service-cluster-ip-range` like this:
```
$ kubectl cluster-info dump | grep -m 1 service-cluster-ip-range
      "--service-cluster-ip-range=10.96.0.0/12",
```

2.If you use cni plugins, `listenInterface` may be cni0, tunl0, otherwise `listenInterface` may be docker0, use ifconfig to check it.
