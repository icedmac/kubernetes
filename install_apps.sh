#!/usr/bin/env bash
set -euo pipefail

# Variables par défaut (dépôt officiel Argo CD, branche stable, chemin manifests)
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/argoproj/argo-cd.git}"
GIT_PATH="${GIT_PATH:-manifests}"
GIT_TARGET_REVISION="${GIT_TARGET_REVISION:-stable}"
NAMESPACE="argocd"

echo "Création du namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "Installation d'Argo CD depuis le manifeste officiel..."
kubectl apply -n $NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Attente que les pods Argo CD soient prêts (cette étape peut prendre quelques minutes)..."
kubectl wait --for=condition=Ready pods --all -n $NAMESPACE --timeout=300s

echo "Création de l'Application Argo CD pour la self-management..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-self-managed
  namespace: $NAMESPACE
spec:
  project: default
  source:
    repoURL: '$GIT_REPO_URL'
    targetRevision: '$GIT_TARGET_REVISION'
    path: $GIT_PATH
  destination:
    namespace: $NAMESPACE
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "Argo CD est installé et gérera désormais sa propre configuration depuis $GIT_REPO_URL ($GIT_TARGET_REVISION/$GIT_PATH)."
echo "Vérifiez l'état de l'Application avec : kubectl get application -n $NAMESPACE"
