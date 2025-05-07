#!/usr/bin/env bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#
oc delete -f 5gran-gnb-configmap.yaml
oc delete -f 5gran-ue-configmap.yaml
oc delete -f 5gran.yaml
rm 5gran-gnb-configmap.yaml

echo "Bye Bye The 5GRAN!"
