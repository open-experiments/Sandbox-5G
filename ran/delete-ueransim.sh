#!/usr/bin/env bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#
NAMESPACE="open5gran"
echo "Uninstalling open5gran..."
oc project ${NAMESPACE}
oc delete -f 5gran-gnb-configmap.yaml
oc delete -f 5gran-ue-configmap.yaml
oc delete -f 5gran.yaml
rm 5gran-gnb-configmap.yaml

echo "Bye Bye The 5GRAN!"
