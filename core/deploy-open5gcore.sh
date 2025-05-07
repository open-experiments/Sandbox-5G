#!/bin/bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#

set -e

NAMESPACE="open5gcore"
MONGODB_URI="mongodb://mongo/open5gs"  # Using service name for MongoDB
IMSI="999700000000001"
KI="465B5CE8B199B49FAA5F0A2EE238A6BC"
OPC="E8ED289DEBA952E4283B54E88E6183CA"
APN="internet"
SST="1"
SD="000001"
MCC="999"
MNC="70"
TAC="7"
IMAGE_REGISTRY="docker.io"
IMAGE_REPOSITORY="gradiant/open5gs"
IMAGE_TAG="2.7.5"
WEBUI_IMAGE_REPOSITORY="gradiant/open5gs-webui"
DBCTL_IMAGE_REPOSITORY="gradiant/open5gs-dbctl"

echo -e "Configuring privileged access for all containers in the namespace\n"
# Configure the namespace with necessary SCCs
oc adm policy add-scc-to-user anyuid -z default -n ${NAMESPACE} || true
oc adm policy add-scc-to-user hostaccess -z default -n ${NAMESPACE} || true
oc adm policy add-scc-to-user hostmount-anyuid -z default -n ${NAMESPACE} || true
oc adm policy add-scc-to-user privileged -z default -n ${NAMESPACE} || true
oc adm policy add-scc-to-user net-bind-service -z default -n ${NAMESPACE} || true

oc create secret generic mongodb-ca --from-file=./etc/rds-combined-ca-bundle.pem

echo -e "Creating Network Policies\n"
oc apply -f ./etc/allow-sbi.yaml -n ${NAMESPACE}
oc apply -f ./etc/scc-5gcore.yaml -n ${NAMESPACE}


# Deploy MongoDB first as it's required by other components
echo -e "Deploying MongoDB\n"
oc process -f ./templates/open5gs-mongodb.yaml \
  -p NAME=open5gs-mongodb \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=docker.io \
  -p IMAGE_REPOSITORY=bitnami/mongodb \
  -p IMAGE_TAG=latest \
  -p MONGODB_STORAGE_SIZE=10Gi \
  | oc apply -f -

echo -e "Waiting for MongoDB to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-mongodb -n ${NAMESPACE} || true

# Deploy NRF first as it's required for service discovery
echo -e "Deploying NRF\n"
oc process -f ./templates/open5gs-nrf.yaml \
  -p NAME=open5gs-nrf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  | oc apply -f -

echo -e "Waiting for NRF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-nrf -n ${NAMESPACE} || true

# Deploy UDR
echo -e "Deploying UDR\n"
oc process -f ./templates/open5gs-udr.yaml \
  -p NAME=open5gs-udr \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p NRF_SVC=open5gs-nrf \
  -p MONGODB_URI=${MONGODB_URI} \
  | oc apply -f -

# Wait for UDR to be ready
echo -e "Waiting for UDR to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-udr -n ${NAMESPACE} || true

# Deploy UDM
echo -e "Deploying UDM\n"
oc process -f ./templates/open5gs-udm.yaml \
  -p NAME=open5gs-udm \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p NRF_SVC=open5gs-nrf \
  -p UDR_SVC=open5gs-udr \
  | oc apply -f -

# Wait for UDM to be ready
echo -e "Waiting for UDM to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-udm -n ${NAMESPACE} || true

# Deploy AUSF
echo -e "Deploying AUSF\n"
oc process -f ./templates/open5gs-ausf.yaml \
  -p NAME=open5gs-ausf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p NRF_SVC=open5gs-nrf \
  -p UDM_SVC=open5gs-udm \
  | oc apply -f -

# Wait for AUSF to be ready
echo -e "Waiting for AUSF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-ausf -n ${NAMESPACE} || true

# Deploy PCF
echo -e "Deploying PCF\n"
oc process -f ./templates/open5gs-pcf.yaml \
  -p NAME=open5gs-pcf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p NRF_SVC=open5gs-nrf \
  -p MONGODB_URI=${MONGODB_URI} \
  | oc apply -f -

# Wait for PCF to be ready
echo -e "Waiting for PCF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-pcf -n ${NAMESPACE} || true

# Deploy NSSF
echo -e "Deploying NSSF\n"
oc process -f ./templates/open5gs-nssf.yaml \
  -p NAME=open5gs-nssf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p NRF_SVC=open5gs-nrf \
  -p MCC=${MCC} \
  -p MNC=${MNC} \
  -p SST=${SST} \
  -p SD=${SD} \
  | oc apply -f -

# Wait for NSSF to be ready
echo -e "Waiting for NSSF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-nssf -n ${NAMESPACE} || true

# Deploy AMF
echo -e "Deploying AMF\n"
oc process -f ./templates/open5gs-amf.yaml \
  -p NAME=open5gs-amf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p MCC=${MCC} \
  -p MNC=${MNC} \
  -p TAC=${TAC} \
  -p SST=${SST} \
  -p SD=${SD} \
  -p NRF_SVC=open5gs-nrf \
  | oc apply -f -

# Wait for AMF to be ready
echo -e "Waiting for AMF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-amf -n ${NAMESPACE} || true

# Deploy UPF
echo -e "Deploying UPF\n"
oc process -f ./templates/open5gs-upf.yaml \
  -p NAME=open5gs-upf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  | oc apply -f -

# Wait for UPF to be ready
echo -e "Waiting for UPF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-upf -n ${NAMESPACE} || true

# Deploy SMF
echo -e "Deploying SMF\n"
oc process -f ./templates/open5gs-smf.yaml \
  -p NAME=open5gs-smf \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p MCC=${MCC} \
  -p MNC=${MNC} \
  -p UPF_SVC=open5gs-upf \
  -p NRF_SVC=open5gs-nrf \
  | oc apply -f -

# Wait for SMF to be ready
echo -e "Waiting for SMF to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-smf -n ${NAMESPACE} || true

# Deploy WebUI
echo -e "Deploying WebUI\n"
oc process -f ./templates/open5gs-webui.yaml \
  -p NAME=open5gs-webui \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${WEBUI_IMAGE_REPOSITORY} \
  -p IMAGE_TAG=${IMAGE_TAG} \
  -p MONGODB_URI=${MONGODB_URI} \
  | oc apply -f -

# Wait for WebUI to be ready
echo -e "Waiting for WebUI to be ready...\n"
oc wait --for=condition=available --timeout=180s deployment/open5gs-webui -n ${NAMESPACE} || true

# Deploy subscriber population tool
echo -e "Deploying subscriber management tool\n"
oc process -f ./templates/open5gs-populate.yaml \
  -p NAME=open5gs-populate \
  -p NAMESPACE=${NAMESPACE} \
  -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
  -p IMAGE_REPOSITORY=${DBCTL_IMAGE_REPOSITORY} \
  -p IMAGE_TAG=0.10.3 \
  -p MONGODB_URI=${MONGODB_URI} \
  -p IMSI=${IMSI} \
  -p KI=${KI} \
  -p OPC=${OPC} \
  -p APN=${APN} \
  -p SST=${SST} \
  -p SD=${SD} \
  | oc apply -f -

echo -e "Setting up route to access WebUI\n"
WEBUI_ROUTE=$(oc get route open5gs-webui -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || \
  oc create route edge --service=open5gs-webui --port=3000 -n ${NAMESPACE} | grep -o "open5gs-webui-.*\..*" | head -1)

echo "Open5GS 5G Core deployment completed successfully!"
if [ -n "$WEBUI_ROUTE" ]; then
  echo "WebUI is available at: https://${WEBUI_ROUTE}"
  echo "Default credentials: admin / 1423"
else
  echo "WebUI route not found. You may need to create it manually."
fi

echo -e "\nDisplaying pod status:"
oc get pods -n ${NAMESPACE}