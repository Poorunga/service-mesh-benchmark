#!/bin/bash

script_location="$(dirname "${BASH_SOURCE[0]}")"
istio_profile=minimal

# benchmark params
app_count=59
duration=600
init_delay=10

function init_bench_env() {
    nodes=()
    for node in $(kubectl get nodes | grep "Ready" | awk '{print $1}'); do
        nodes[${#nodes[*]}]=$node
    done

    [ 2 -gt ${#nodes[*]} ] && \
        echo -e "Cluster has less than 2 working nodes" && \
        exit 1

    # The first node is used as a benchmark node
    kubectl label node ${nodes[0]} role=benchmark --overwrite=true

    # The remaining nodes are used as workload nodes
    for node in ${nodes[@]:1}; do
        kubectl label node $node role=workload --overwrite=true
    done

    echo "Installing helm"
    wget https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz -P /tmp
    tar -zxvf /tmp/helm-v3.6.3-linux-amd64.tar.gz -C /tmp
    mv /tmp/linux-amd64/helm /usr/local/bin/

    echo "Installing istioctl"
    istio_version=1.11.2
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$istio_version TARGET_ARCH=x86_64 sh -
    cp istio-$istio_version/bin/istioctl /usr/local/bin/
    rm -rf istio-$istio_version

    echo "Installing prometheus"
    install_prometheus

    echo -e "\n\nSuccessfully initialized the benchmark environment!\n" && \
    echo "Next you can upload Grafana dashboard, please refer to: https://github.com/Poorunga/service-mesh-benchmark#upload-grafana-dashboard"
}
# --

function grace() {
    grace=10
    [ -n "$2" ] && grace="$2"

    while true; do
        eval $1
        if [ $? -eq 0 ]; then
            sleep 1
            grace=10
            continue
        fi

        if [ $grace -gt 0 ]; then
            sleep 1
            echo "grace period: $grace"
            grace=$(($grace-1))
            continue
        fi

        break
    done
}
# --

function check_meshed() {
    local ns_prefix="$1"

    echo "Checking for unmeshed pods in '$ns_prefix'"
    kubectl get pods --all-namespaces \
            | grep "$ns_prefix" | grep -vE '[012]/2'

    [ $? -ne 0 ] && return 0

    return 1
}
# --

function install_emojivoto() {
    local mesh="$1"

    echo "Installing emojivoto."

    for num in $(seq 0 1 $app_count); do
        {
            kubectl create namespace emojivoto-$num

            [ "$mesh" == "istio" ] && \
                kubectl label namespace emojivoto-$num istio-injection=enabled

            helm install emojivoto-$num --namespace emojivoto-$num \
                             ${script_location}/../configs/emojivoto/
         } &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 10
}
# --

function install_emojivoto_for_edgemesh() {
    echo "Installing emojivoto for edgemesh."

    for num in $(seq 0 1 $app_count); do
        {
            kubectl create namespace emojivoto-$num

            # Service ports must be named. The key/value pairs of port name must have the following syntax: name: <protocol>[-<suffix>].
            # See https://github.com/kubeedge/edgemesh#getting-started for more information.
            helm install emojivoto-$num --namespace emojivoto-$num \
                    --set proto.grpc=tcp-0 --set proto.prom=tcp-1 \
                    --set proto.http=http-0 \
                    ${script_location}/../configs/emojivoto/
         } &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 10
}
# --

function restart_emojivoto_pods() {

    for num in $(seq 0 1 $app_count); do
        local ns="emojivoto-$num"
        echo "Restarting pods in $ns"
        {  local pods="$(kubectl get -n "$ns" pods | grep -vE '^NAME' | awk '{print $1}')"
            kubectl delete -n "$ns" pods $pods --wait; } &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 10
}
# --

function delete_emojivoto() {
    echo "Deleting emojivoto."

    for i in $(seq 0 1 $app_count); do
        { helm uninstall emojivoto-$i --namespace emojivoto-$i;
          kubectl delete namespace emojivoto-$i --wait; } &
    done

    wait

    grace "kubectl get namespaces | grep emojivoto"
}
# --

function install_benchmark() {
    local mesh="$1"
    local rps="$2"

    local app_count=$(kubectl get namespaces | grep emojivoto | wc -l)

    echo "Running $mesh benchmark"
    kubectl create ns benchmark
    [ "$mesh" == "istio" ] && \
        kubectl label namespace benchmark istio-injection=enabled
    if [ "$mesh" != "bare-metal" ] ; then
        helm install benchmark --namespace benchmark \
            --set wrk2.serviceMesh="$mesh" \
            --set wrk2.app.count="$app_count" \
            --set wrk2.RPS="$rps" \
            --set wrk2.duration=$duration \
            --set wrk2.connections=128 \
            --set wrk2.initDelay=$init_delay \
            ${script_location}/../configs/benchmark/
    else
        helm install benchmark --namespace benchmark \
            --set wrk2.app.count="$app_count" \
            --set wrk2.RPS="$rps" \
            --set wrk2.duration=$duration \
            --set wrk2.initDelay=$init_delay \
            --set wrk2.connections=128 \
            ${script_location}/../configs/benchmark/
    fi
}
# --

function run_bench() {
    local mesh="$1"
    local rps="$2"

    install_benchmark "$mesh" "$rps"
    grace "kubectl get pods -n benchmark | grep wrk2-prometheus | grep -v Running" 10

    echo "Benchmark started."

    while kubectl get jobs -n benchmark \
            | grep wrk2-prometheus \
            | grep -qv 1/1; do
        kubectl logs \
                --tail 1 -n benchmark  jobs/wrk2-prometheus -c wrk2-prometheus
        sleep 10
    done

    echo "Benchmark concluded. Updating summary metrics."
    helm install --create-namespace --namespace metrics-merger \
        metrics-merger ${script_location}/../configs/metrics-merger/
    sleep 5
    while kubectl get jobs -n metrics-merger \
            | grep wrk2-metrics-merger \
            | grep  -v "1/1"; do
        sleep 1
    done

    kubectl logs -n metrics-merger jobs/wrk2-metrics-merger

    echo "Cleaning up."
    helm uninstall benchmark --namespace benchmark
    kubectl delete ns benchmark --wait
    helm uninstall --namespace metrics-merger metrics-merger
    kubectl delete ns metrics-merger --wait
}
# --

function install_istio() {
    echo "Installing istio"
    istioctl install --set profile=$istio_profile -y
    grace "kubectl get pods --all-namespaces | grep istio-system | grep -v Running"
}
# --

function delete_istio() {
    istioctl manifest generate --set profile=$istio_profile | kubectl delete --ignore-not-found=true -f -
    kubectl delete namespace istio-system --now --timeout=30s
    grace "kubectl get namespaces | grep istio-system" 1
    sleep 30    # extra sleep to let istio initialise. Sidecar injection will
                #  fail otherwise.
}
# --

function install_edgemesh() {
    echo "Installing edgemesh"
    # some services add noproxy=edgemesh label
    ${script_location}/../edgemesh-tools/bin/noproxy --namespaces kube-system,monitoring
    # get schedule node, first value is node name, second value is node ip
    schedule_node=$(${script_location}/../edgemesh-tools/bin/select)
    array=(${schedule_node//,/ })
    [ 2 -ne ${#array[@]} ] && echo "invalid schedule node, exit" && exit 1
    node_name="${array[0]}"
    node_ip="${array[1]}"
    # install
    kubectl create ns kubeedge
    helm install edgemesh --namespace kubeedge \
      --set server.nodeName=$node_name --set server.publicIP=$node_ip \
      --set agent.subNet=10.247.0.0/16 --set agent.listenInterface=docker0 \
      ${script_location}/../configs/edgemesh/
    grace "kubectl get pods --all-namespaces | grep kubeedge | grep -v Running"
}
# --

function delete_edgemesh() {
    helm uninstall edgemesh --namespace kubeedge
    kubectl delete ns kubeedge --wait
    grace "kubectl get namespaces | grep kubeedge" 1
    # remove services label
    kubectl label service --all noproxy- -n kube-system
    kubectl label service --all noproxy- -n monitoring
}
# --

function install_prometheus() {
    kubectl create ns monitoring
    # install prometheus-operator
    helm install prometheus-operator --namespace monitoring \
      ${script_location}/../configs/prometheus-operator/
    grace "kubectl get pods --all-namespaces | grep monitoring | grep prometheus-operator | grep -v Running"
    # install pushgateway
    helm install pushgateway --namespace monitoring \
      ${script_location}/../configs/pushgateway/
    grace "kubectl get pods --all-namespaces | grep monitoring | grep pushgateway | grep -v Running"
}
# --

function delete_prometheus() {
    helm uninstall prometheus-operator -n monitoring
    helm uninstall pushgateway -n monitoring
    kubectl delete ns monitoring --wait
    grace "kubectl get namespaces | grep monitoring" 1
}
# --

function run_bare_metal_bench() {
    local rps="$1"

    echo " +++ bare metal benchmark"
    install_emojivoto bare-metal
    run_bench bare-metal $rps
    delete_emojivoto
}
# --

function run_istio_bench() {
    local rps="$1"

    echo " +++ istio benchmark"
    install_istio
    install_emojivoto istio
    while true; do
        check_meshed "emojivoto-" && {
            echo "  ++ Emojivoto is fully meshed."
            break; }
        echo " !!! Emojivoto is not fully meshed."
        echo "     Deleting and re-deploying Istio."
        delete_istio
        install_istio
        echo " !!!  Restarting all Emojivoto pods."
        restart_emojivoto_pods
    done
    run_bench istio $rps
    delete_emojivoto

    echo "Removing istio"
    delete_istio
}
# --

function run_edgemesh_bench() {
    local rps="$1"

    echo " +++ edgemesh benchmark"
    install_edgemesh
    install_emojivoto_for_edgemesh
    run_bench edgemesh $rps
    delete_emojivoto

    echo "Removing edgemesh"
    delete_edgemesh
}
# --

function run_benchmarks() {
    for rps in 20 100 500 2500; do
        for repeat in 1 2 3 4 5; do
            echo "########## Run #$repeat w/ $rps RPS"
            run_bare_metal_bench $rps
            run_edgemesh_bench $rps
            run_istio_bench $rps
        done
    done
}
# --

$@
