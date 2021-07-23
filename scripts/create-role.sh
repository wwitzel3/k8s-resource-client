#!/bin/bash
set -x

if [[ -z "$1" ]] ;then
  echo "usage: $0 <username>"
  exit 1
fi

user=$1
kubectl create sa ${user}
secret=$(kubectl get sa ${user} -o json | jq -r .secrets[].name)
kubectl get secret ${secret} -o json | jq -r '.data["ca.crt"]' | base64 -d > ca.crt

user_token=$(kubectl get secret ${secret} -o json | jq -r '.data["token"]' | base64 -d)
c=`kubectl config current-context`
cluster_name=`kubectl config get-contexts $c | awk '{print $3}' | tail -n 1`
endpoint=`kubectl config view -o jsonpath="{.clusters[?(@.name == \"${cluster_name}\")].cluster.server}"`

# Set up the config
KUBECONFIG=k8s-${user}-conf kubectl config set-cluster ${cluster_name} \
    --embed-certs=true \
    --server=${endpoint} \
    --certificate-authority=./ca.crt

KUBECONFIG=k8s-${user}-conf kubectl config set-credentials ${user}-${cluster_name#cluster-} --token=${user_token}
KUBECONFIG=k8s-${user}-conf kubectl config set-context ${user}-${cluster_name#cluster-} \
    --cluster=${cluster_name} \
    --user=${user}-${cluster_name#cluster-}
KUBECONFIG=k8s-${user}-conf kubectl config use-context ${user}-${cluster_name#cluster-}

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
  name: test-read-only
  namespace: default
rules:
- apiGroups:
  - ""
  resources: ["pods"]
  verbs:
  - get
  - list
  - watch
EOF

cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: view-${user}-global
subjects:
- kind: ServiceAccount
  name: ${user}
  namespace: default
roleRef:
  kind: ClusterRole
  name: test-read-only
  apiGroup: rbac.authorization.k8s.io

EOF


echo "done! Test with: "
echo "export KUBECONFIG=k8s-${user}-conf"
echo "kubectl get pods"
