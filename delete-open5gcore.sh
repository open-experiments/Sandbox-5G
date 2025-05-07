#!/bin/bash
#Author: Fatih E.NAR
#Date: 4/11/2075 
#
NAMESPACE="open5gcore"

echo "Deleting all Open5GS resources..."

cd core

# Delete Deployments to gracefully terminate pods
oc delete deployment -l app.kubernetes.io/part-of=open5gcore -n ${NAMESPACE}

# Delete Services
oc delete service -l app.kubernetes.io/part-of=open5gcore -n ${NAMESPACE}

# Delete Routes
oc delete route -l app.kubernetes.io/part-of=open5gcore -n ${NAMESPACE}

# Delete ConfigMaps
oc delete configmap -l app.kubernetes.io/part-of=open5gcore -n ${NAMESPACE}

# Delete PVCs (Warning: This will remove persistent data)
echo "Warning: This will delete all persistent volume claims for MongoDB."
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  oc delete pvc -l app.kubernetes.io/part-of=open5gcore -n ${NAMESPACE}
  echo "Persistent volume claims deleted."
else
  echo "Skipping deletion of persistent volume claims."
fi

# Optionally delete the project (uncomment to use)
# echo "Deleting project ${NAMESPACE}..."
# oc delete project ${NAMESPACE}

oc delete secret mongodb-ca
oc delete -f ./etc/scc-5gcore.yaml
oc delete -f ./etc/allow-sbi.yaml

echo "Open5GS 5G Core cleanup completed successfully!"

cd ..