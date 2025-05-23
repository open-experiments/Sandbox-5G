#!/bin/bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#
NAMESPACE="open5gcore"
echo "Installing open5gcore..."
oc new-project ${NAMESPACE}
oc project ${NAMESPACE}
echo "Labeling open5gcore namespace as a part of the mesh"
oc label namespace ${NAMESPACE} istio-injection=enabled
echo "Enabling pod monitor in open5gcore namespace"
oc apply -f ./resources/Monitoring/podMonitor.yaml -n ${NAMESPACE}

echo "Deploying open5gcore CNFs"
cd core
./deploy-open5gcore.sh
oc wait --for=condition=Ready pods --all -n ${NAMESPACE} --timeout 60s
cd ..

oc apply -f ./resources/open5gcore/open5gcore-gateway.yaml -n ${NAMESPACE}
echo "Waiting for open5gcore CNFs to become ready..."
oc wait --for=condition=Ready pods --all -n ${NAMESPACE} --timeout 60s

echo "Deployment finished!"

# this env will be used in traffic generator
export INGRESSHOST=$(oc get route istio-ingressgateway -n istio-ingress -o=jsonpath='{.spec.host}')
KIALI_HOST=$(oc get route kiali -n istio-system -o=jsonpath='{.spec.host}')
