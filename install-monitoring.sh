#!/bin/bash
#Author: Fatih E.NAR
#Date: 5/07/2025 
#

set -e

NAMESPACE="open5gcore"
MONITORING_NAMESPACE="open5gs-monitoring"
DIR="$(dirname "$0")"
DASHBOARD_DIR="${DIR}/resources/dashboard"
MONITORING_DIR="${DIR}/resources/Monitoring"

# Set timeout for component readiness (5 minutes)
TIMEOUT=300

echo -e "Creating Monitoring Namespace: ${MONITORING_NAMESPACE}\n"
oc new-project ${MONITORING_NAMESPACE} || true

# First create the RBAC permissions needed for Prometheus to access open5gcore namespace
echo -e "Creating ServiceAccount and RBAC for Prometheus...\n"
cat ${MONITORING_DIR}/prometheus-rbac.yaml | sed "s/\${NAMESPACE}/${NAMESPACE}/g" | oc apply -f -

echo -e "Creating ServiceMonitor for Open5GS components\n"
cat ${MONITORING_DIR}/serviceMonitor.yaml | sed "s/\${NAMESPACE}/${NAMESPACE}/g" | oc apply -n ${MONITORING_NAMESPACE} -f -

echo -e "Deploying Prometheus\n"
cat ${MONITORING_DIR}/prometheus-config.yaml | sed "s/\${NAMESPACE}/${NAMESPACE}/g" | oc apply -n ${MONITORING_NAMESPACE} -f -
oc apply -f ${MONITORING_DIR}/prometheus-deployment.yaml -n ${MONITORING_NAMESPACE}

# Create ConfigMap for Grafana dashboards
echo -e "Creating Grafana dashboards ConfigMap\n"
cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
data:
  open5gs-dashboard.json: |
$(cat ${DASHBOARD_DIR}/open5gs-dashboard.json | sed 's/^/    /')
  5g-network-stats.json: |
$(cat ${DASHBOARD_DIR}/5g-network-stats.json | sed 's/^/    /')
EOF

echo -e "Deploying FluentBit for log collection\n"
cat ${MONITORING_DIR}/fluent-bit-config.yaml | sed "s/\${NAMESPACE}/${NAMESPACE}/g" | oc apply -n ${MONITORING_NAMESPACE} -f -

# Enable user workload monitoring in OCP
echo -e "Enabling user workload monitoring in OCP\n"
oc apply -f ${MONITORING_DIR}/ocpUserMonitoring.yaml

# Wait for Prometheus to be ready with timeout
echo -e "Waiting for Prometheus to become ready...\n"
START_TIME=$(date +%s)

# Wait for Prometheus pod to be Running
until oc get pods -l app=prometheus -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.phase}' | grep -q Running; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - START_TIME)) -gt ${TIMEOUT} ]; then
    echo "Timeout waiting for Prometheus pod to enter Running state. Continuing anyway..."
    break
  fi
  echo "Waiting for Prometheus pod to be running..."
  sleep 10
done

# Wait for Prometheus pod to be Ready
echo "Waiting for Prometheus to become ready (based on readiness probe)..."
until oc get pods -l app=prometheus -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - START_TIME)) -gt ${TIMEOUT} ]; then
    echo "Timeout waiting for Prometheus readiness. Continuing anyway..."
    break
  fi
  echo "Waiting for Prometheus to become ready..."
  sleep 10
done

# Get the routes for accessing the monitoring dashboards
PROMETHEUS_ROUTE=$(oc get route prometheus -n ${MONITORING_NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "prometheus-route-not-found")
GRAFANA_ROUTE=$(oc get route grafana -n ${MONITORING_NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "grafana-route-not-found")

echo -e "\nMonitoring deployment completed successfully!"
echo -e "Access the monitoring dashboards at:"
echo -e "  Prometheus: https://${PROMETHEUS_ROUTE}"
echo -e "  Grafana: https://${GRAFANA_ROUTE} (Default credentials: admin/admin)"
echo -e "\nThe monitoring stack is now collecting metrics from your Open5GS deployment."