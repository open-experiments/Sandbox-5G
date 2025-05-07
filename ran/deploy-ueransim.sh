#!/bin/bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
# Script to deploy UERANSIM with dynamic AMF IP discovery

# Get the AMF IP address
AMF_IP=$(oc get services -n open5gcore | grep open5gs-amf | awk '{print $3}')

echo "AMF IP:"
echo $AMF_IP

# Create temp file with correct format
cat > 5gran-gnb-configmap.yaml << EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: 5gran-gnb-config
data:
  5gran-gnb-configmap.yaml: |
    mcc: '999'          # Mobile Country Code value
    mnc: '70'           # Mobile Network Code value (2 or 3 digits)
    nci: '0x0000000100'
    idLength: 32        # NR gNB ID length in bits [22...32]
    tac: 7            # Tracking Area Code
    linkIp: 0.0.0.0
    ngapIp: 0.0.0.0
    gtpIp: 0.0.0.0
    # List of AMF address information
    amfConfigs:
      - address: ${AMF_IP}
        port: 38412
    # List of supported S-NSSAIs by this gNB
    slices:
      - sst: 1
        sd: "000001"
    # Indicates whether or not SCTP stream number errors should be ignored.
    ignoreStreamIds: 'true'
EOF

# Deploy the 5GRAN components
oc apply -f 5gran-gnb-configmap.yaml
oc apply -f 5gran-ue-configmap.yaml
oc apply -f 5gran.yaml

echo "Enjoy The 5GRAN!"