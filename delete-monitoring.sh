#!/bin/bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#
# Script to remove monitoring components installed by deploy-monitoring.sh

set -e

MONITORING_NAMESPACE="open5gs-monitoring"

echo "Deleting monitoring components from namespace ${MONITORING_NAMESPACE}..."

# Delete Kibana resources
echo "Deleting Kibana resources..."
oc delete route kibana -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete service kibana -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete deployment kibana -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Delete Elasticsearch resources
echo "Deleting Elasticsearch resources..."
oc delete service elasticsearch -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete deployment elasticsearch -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Delete FluentBit resources
echo "Deleting FluentBit resources..."
oc delete daemonset fluent-bit -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete configmap fluent-bit-config -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete clusterrolebinding fluent-bit-read --ignore-not-found=true
oc delete clusterrole fluent-bit-read --ignore-not-found=true
oc delete serviceaccount fluent-bit -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Delete Grafana resources
echo "Deleting Grafana resources..."
oc delete route grafana -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete service grafana -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete deployment grafana -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete configmap grafana-dashboards -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete configmap grafana-dashboards-config -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete configmap grafana-datasources -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Delete Prometheus resources
echo "Deleting Prometheus resources..."
oc delete route prometheus -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete service prometheus -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete deployment prometheus -n ${MONITORING_NAMESPACE} --ignore-not-found=true
oc delete configmap prometheus-config -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Delete ServiceMonitor
echo "Deleting ServiceMonitor resources..."
oc delete servicemonitor open5gs-servicemonitor -n ${MONITORING_NAMESPACE} --ignore-not-found=true

# Ask user if they want to delete the namespace
echo "Do you want to delete the entire monitoring namespace (${MONITORING_NAMESPACE})?"
read -p "This will remove all resources in the namespace. Proceed? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Deleting namespace ${MONITORING_NAMESPACE}..."
  oc delete project ${MONITORING_NAMESPACE}
  echo "Namespace ${MONITORING_NAMESPACE} deleted."
else
  echo "Keeping namespace ${MONITORING_NAMESPACE}."
fi

echo "Monitoring cleanup completed successfully!"