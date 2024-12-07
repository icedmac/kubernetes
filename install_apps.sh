#!/usr/bin/env bash
set -euo pipefail

# Variables à ajuster
GIT_REPO_URL="https://github.com/votre-organisation/votre-repo.git"
GIT_PATH="argocd"  # Le chemin dans le repo qui contient les manifests ArgoCD
NAMESPACE="argocd"

echo "Création du namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "Installation d'Argo CD depuis le manifeste officiel..."
kubectl apply -n $NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Attente que les pods Argo CD soient prêts (cette étape est optionnelle, elle peut prendre du temps)..."
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
    targetRevision: main
    path: $GIT_PATH
  destination:
    namespace: $NAMESPACE
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "Argo CD est installé et une Application est créée pour qu'il se gère lui-même."
echo "Vérifiez l'état de l'Application avec : kubectl get application -n $NAMESPACE"
