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

# Create Prometheus service and route
cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  labels:
    app: prometheus
spec:
  selector:
    app: prometheus
  ports:
  - name: web
    port: 9090
    targetPort: 9090
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: prometheus
spec:
  to:
    kind: Service
    name: prometheus
  port:
    targetPort: web
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

echo -e "Deploying Grafana\n"
cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
      access: proxy
      isDefault: true
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-config
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      updateIntervalSeconds: 10
      options:
        path: /var/lib/grafana/dashboards
EOF

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

# Deploy Grafana
cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  labels:
    app: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.0.3
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        - name: GF_USERS_ALLOW_SIGN_UP
          value: "false"
        - name: GF_INSTALL_PLUGINS
          value: "grafana-piechart-panel,grafana-clock-panel"
        volumeMounts:
        - name: grafana-datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: grafana-dashboards-config
          mountPath: /etc/grafana/provisioning/dashboards
        - name: grafana-dashboards
          mountPath: /var/lib/grafana/dashboards
        - name: grafana-storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 30
          timeoutSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 10
          timeoutSeconds: 5
      volumes:
      - name: grafana-datasources
        configMap:
          name: grafana-datasources
      - name: grafana-dashboards-config
        configMap:
          name: grafana-dashboards-config
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboards
      - name: grafana-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  labels:
    app: grafana
spec:
  selector:
    app: grafana
  ports:
  - name: http
    port: 3000
    targetPort: 3000
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: grafana
spec:
  to:
    kind: Service
    name: grafana
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

echo -e "Deploying FluentBit for log collection\n"
cat ${MONITORING_DIR}/fluent-bit-config.yaml | sed "s/\${NAMESPACE}/${NAMESPACE}/g" | oc apply -n ${MONITORING_NAMESPACE} -f -

cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluent-bit
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluent-bit-read
rules:
- apiGroups: [""]
  resources:
  - namespaces
  - pods
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fluent-bit-read
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: fluent-bit-read
subjects:
- kind: ServiceAccount
  name: fluent-bit
  namespace: ${MONITORING_NAMESPACE}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  labels:
    app: fluent-bit
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:2.1.9
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluent-bit-config
          mountPath: /fluent-bit/etc/
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: 2020
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: fluent-bit-config
        configMap:
          name: fluent-bit-config
EOF

echo -e "Deploying Elasticsearch for log storage\n"
cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  labels:
    app: elasticsearch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
      annotations:
        co.elastic.logs/enabled: "true"
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:8.9.0
        env:
        - name: discovery.type
          value: single-node
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
        - name: xpack.security.enabled
          value: "false"
        - name: xpack.security.transport.ssl.enabled
          value: "false"
        - name: node.store.allow_mmap
          value: "false"
        ports:
        - containerPort: 9200
          name: http
        - containerPort: 9300
          name: transport
        volumeMounts:
        - name: elasticsearch-data
          mountPath: /usr/share/elasticsearch/data
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
        readinessProbe:
          httpGet:
            path: /_cluster/health
            port: 9200
            scheme: HTTP
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /_cluster/health
            port: 9200
            scheme: HTTP
          initialDelaySeconds: 120
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: elasticsearch-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  labels:
    app: elasticsearch
spec:
  selector:
    app: elasticsearch
  ports:
  - name: http
    port: 9200
    targetPort: 9200
  - name: transport
    port: 9300
    targetPort: 9300
EOF

echo -e "Deploying Kibana for log visualization\n"
cat <<EOF | oc apply -n ${MONITORING_NAMESPACE} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  labels:
    app: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:8.9.0
        env:
        - name: ELASTICSEARCH_HOSTS
          value: http://elasticsearch:9200
        - name: XPACK_SECURITY_ENABLED
          value: "false"
        ports:
        - containerPort: 5601
          name: http
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        readinessProbe:
          httpGet:
            path: /api/status
            port: 5601
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: /api/status
            port: 5601
          initialDelaySeconds: 120
          periodSeconds: 20
          timeoutSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  labels:
    app: kibana
spec:
  selector:
    app: kibana
  ports:
  - name: http
    port: 5601
    targetPort: 5601
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kibana
spec:
  to:
    kind: Service
    name: kibana
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

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

# Wait for Elasticsearch to be ready with timeout
echo -e "Waiting for Elasticsearch to become ready...\n"
START_TIME=$(date +%s)

# Wait for Elasticsearch pod to be Running
until oc get pods -l app=elasticsearch -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - START_TIME)) -gt ${TIMEOUT} ]; then
    echo "Timeout waiting for Elasticsearch pod to enter Running state. Continuing anyway..."
    break
  fi
  echo "Waiting for Elasticsearch pod to be running..."
  sleep 10
done

# Wait for Elasticsearch pod to be Ready
echo "Waiting for Elasticsearch to become ready (based on readiness probe)..."
until oc get pods -l app=elasticsearch -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - START_TIME)) -gt ${TIMEOUT} ]; then
    echo "Timeout waiting for Elasticsearch readiness. Continuing anyway..."
    break
  fi
  echo "Waiting for Elasticsearch to become ready..."
  sleep 10
done

# Wait for Kibana to be ready with timeout
echo -e "Waiting for Kibana to become ready...\n"
START_TIME=$(date +%s)

# Wait for Kibana pod to be Running
until oc get pods -l app=kibana -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - START_TIME)) -gt ${TIMEOUT} ]; then
    echo "Timeout waiting for Kibana pod to enter Running state. Continuing anyway..."
    break
  fi
  echo "Waiting for Kibana pod to be running..."
  sleep 10
done

# Wait for Kibana pod to be Ready
echo "Waiting for Kibana to become ready (based on readiness probe)..."
until oc get pods -l app=kibana -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - START_TIME)) -gt ${TIMEOUT} ]; then
    echo "Timeout waiting for Kibana readiness. Continuing anyway..."
    break
  fi
  echo "Waiting for Kibana to become ready..."
  sleep 10
done

# Create Kibana index pattern if Kibana is ready
if oc get pods -l app=kibana -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
  echo -e "Setting up Kibana index patterns for Open5GS logs...\n"
  echo "Creating Kibana index pattern..."
  oc exec -n ${MONITORING_NAMESPACE} $(oc get pods -l app=kibana -n ${MONITORING_NAMESPACE} -o jsonpath='{.items[0].metadata.name}') -- curl -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" http://localhost:5601/api/saved_objects/index-pattern/open5gs -d '{"attributes":{"title":"open5gs-*","timeFieldName":"@timestamp"}}' || echo "Failed to create Kibana index pattern. You may need to create it manually."
else
  echo "Kibana is not ready yet. Index pattern will need to be created manually."
fi

# Get the routes for accessing the monitoring dashboards
PROMETHEUS_ROUTE=$(oc get route prometheus -n ${MONITORING_NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "prometheus-route-not-found")
GRAFANA_ROUTE=$(oc get route grafana -n ${MONITORING_NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "grafana-route-not-found")
KIBANA_ROUTE=$(oc get route kibana -n ${MONITORING_NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "kibana-route-not-found")

echo -e "\nMonitoring deployment completed successfully!"
echo -e "Access the monitoring dashboards at:"
echo -e "  Prometheus: https://${PROMETHEUS_ROUTE}"
echo -e "  Grafana: https://${GRAFANA_ROUTE} (Default credentials: admin/admin)"
echo -e "  Kibana: https://${KIBANA_ROUTE}"
echo -e "\nThe monitoring stack is now collecting metrics from your Open5GS deployment."
echo -e "Note: The custom 5G metrics dashboards assume that Open5GS components expose additional metrics"
echo -e "specific to 5G operations. You may need to extend the components to expose these metrics."