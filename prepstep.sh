#!/bin/bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#
echo "This script installs required operators & services - This is to run once only!!!"

oc apply -f subscriptions.yaml
echo "Waiting till all operators pods are ready"
until oc get pods -n openshift-operators | grep servicemesh-operator3 | grep Running; do echo "Waiting for servicemesh-operator3 to be running."; sleep 10;done
until oc get pods -n openshift-operators | grep kiali-operator | grep Running; do echo "Waiting for kiali-operator to be running."; sleep 10;done
until oc get pods -n openshift-operators | grep opentelemetry-operator | grep Running; do echo "Waiting for opentelemetry-operator to be running."; sleep 10;done
until oc get pods -n openshift-operators | grep tempo-operator | grep Running; do echo "Waiting for tempo-operator to be running."; sleep 10;done

echo "All operators were installed successfully$"
oc get pods -n openshift-operators

echo "Enabling Gateway API"
oc get crd gateways.gateway.networking.k8s.io &> /dev/null ||  { oc kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | oc apply -f -; }

echo "Installing Minio for Tempo"
oc new-project tracing-system
oc apply -f ./resources/TempoOtel/minio.yaml -n tracing-system
echo "Waiting for Minio to become available..."
oc wait --for condition=Available deployment/minio --timeout 150s -n tracing-system

echo "Installing TempoCR"
oc apply -f ./resources/TempoOtel/tempo.yaml -n tracing-system
echo "Waiting for TempoStack to become ready..."
oc wait --for condition=Ready TempoStack/sample --timeout 150s -n tracing-system
echo "Waiting for Tempo deployment to become available..."
oc wait --for condition=Available deployment/tempo-sample-compactor --timeout 150s -n tracing-system

echo "Exposing Jaeger UI route (will be used in kiali ui)"
oc expose svc tempo-sample-query-frontend --port=jaeger-ui --name=tracing-ui -n tracing-system

echo "Installing OpenTelemetryCollector..."
oc new-project opentelemetrycollector
oc apply -f ./resources/TempoOtel/opentelemetrycollector.yaml -n opentelemetrycollector
echo "Waiting for OpenTelemetryCollector deployment to become available..."
oc wait --for condition=Available deployment/otel-collector --timeout 60s -n opentelemetrycollector

echo "Installing OSSM3..."
oc new-project istio-system
echo "Installing IstioCR..."
oc apply -f ./resources/OSSM3/istiocr.yaml  -n istio-system
echo "Waiting for istio to become ready..."
oc wait --for condition=Ready istio/default --timeout 60s  -n istio-system

echo "Installing Telemetry resource..."
oc apply -f ./resources/TempoOtel/istioTelemetry.yaml  -n istio-system
echo "Adding OTEL namespace as a part of the mesh"
oc label namespace opentelemetrycollector istio-injection=enabled

echo "Installing IstioCNI..."
oc new-project istio-cni
oc apply -f ./resources/OSSM3/istioCni.yaml -n istio-cni
echo "Waiting for istiocni to become ready..."
oc wait --for condition=Ready istiocni/default --timeout 60s -n istio-cni

echo "Creating ingress gateway via Gateway API..."
oc new-project istio-ingress
echo "Adding istio-ingress namespace as a part of the mesh"
oc label namespace istio-ingress istio-injection=enabled
oc apply -k ./resources/gateway

echo "$Creating ingress gateway via Istio Deployment..."
#oc new-project istio-ingress
#echo "Adding istio-ingress namespace as a part of the mesh"
#oc label namespace istio-ingress istio-injection=enabled
oc apply -f ./resources/OSSM3/istioIngressGateway.yaml  -n istio-ingress
echo "Waiting for deployment/istio-ingressgateway to become available..."
oc wait --for condition=Available deployment/istio-ingressgateway --timeout 60s -n istio-ingress
echo "Exposing Istio ingress route"
oc expose svc istio-ingressgateway --port=http2 --name=istio-ingressgateway -n istio-ingress

echo "Enabling user workload monitoring in OCP"
oc apply -f ./resources/Monitoring/ocpUserMonitoring.yaml
echo "Enabling service monitor in istio-system namespace"
oc apply -f ./resources/Monitoring/serviceMonitor.yaml -n istio-system
echo "Enabling pod monitor in istio-system namespace"
oc apply -f ./resources/Monitoring/podMonitor.yaml -n istio-system
echo "Enabling pod monitor in istio-ingress namespace"
oc apply -f ./resources/Monitoring/podMonitor.yaml -n istio-ingress

echo "Installing Kiali..."
oc project istio-system
echo "Creating cluster role binding for kiali to read ocp monitoring"
oc apply -f ./resources/Kiali/kialiCrb.yaml -n istio-system
echo "Installing KialiCR..."
export TRACING_INGRESS_ROUTE="http://$(oc get -n tracing-system route tracing-ui -o jsonpath='{.spec.host}')"
cat ./resources/Kiali/kialiCr.yaml | JAEGERROUTE="${TRACING_INGRESS_ROUTE}" envsubst | oc -n istio-system apply -f - 
echo "Waiting for kiali to become ready..."
oc wait --for condition=Successful kiali/kiali --timeout 150s -n istio-system 
oc annotate route kiali haproxy.router.openshift.io/timeout=60s -n istio-system 

echo "Install Kiali OSSM Console plugin..."
oc apply -f ./resources/Kiali/kialiOssmcCr.yaml -n istio-system

echo "Installing Sample RestAPI..."
oc apply -k ./resources/application/kustomize/overlays/pod 

echo "EnablingSCTP...ATTENTION: NODE WILL REBOOT!!!.."
oc apply -f ./resources/enablesctp.yaml