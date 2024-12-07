#!/usr/bin/env bash
set -euo pipefail

# Valeurs par défaut
TOKEN=""
DISCOVERY_HASH=""
CONTROL_PLANE_ENDPOINT="my-control-plane.example.com:6443"
CERTIFICATE_KEY=""

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --token=TOKEN                               Token Bootstrap"
    echo "  --discovery-token-ca-cert-hash=HASH          Hash du CA cert"
    echo "  --control-plane-endpoint=ENDPOINT            Endpoint du control-plane (défaut: $CONTROL_PLANE_ENDPOINT)"
    echo "  --certificate-key=KEY                        Clé de certificat fournie par '--upload-certs' lors de l'init"
    echo "  -h, --help                                   Affiche cette aide"
    exit 0
}

TEMP=$(getopt \
  -o h \
  --long help,token:,discovery-token-ca-cert-hash:,control-plane-endpoint:,certificate-key: \
  -n "$0" -- "$@")

if [ $? != 0 ]; then
    usage
fi

eval set -- "$TEMP"

while true; do
  case "$1" in
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --discovery-token-ca-cert-hash)
      DISCOVERY_HASH="$2"
      shift 2
      ;;
    --control-plane-endpoint)
      CONTROL_PLANE_ENDPOINT="$2"
      shift 2
      ;;
    --certificate-key)
      CERTIFICATE_KEY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Option inconnue : $1"
      usage
      ;;
  esac
done

# Vérifications des paramètres obligatoires
if [ -z "$TOKEN" ] || [ -z "$DISCOVERY_HASH" ] || [ -z "$CERTIFICATE_KEY" ]; then
    echo "Erreur: Vous devez spécifier --token, --discovery-token-ca-cert-hash et --certificate-key."
    usage
fi

echo "Désactivation du swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

echo "Configuration du forwarding IP..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sysctl --system

if ! command -v containerd &>/dev/null; then
    echo "Installation de containerd..."
    apt-get update
    apt-get install -y containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    # Ajustez si nécessaire (ex: SystemdCgroup = true dans le fichier toml)
    systemctl restart containerd
    systemctl enable containerd
fi

echo "Ajout du dépôt Kubernetes (version : $K8S_VERSION, adapté si besoin)..."
apt-get update && apt-get install -y apt-transport-https ca-certificates curl gnupg

mkdir -p /etc/apt/keyrings
K8S_VERSION="v1.31" # Ajustez la version si besoin
curl -fsSL https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/ /" \
    | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
if ! command -v kubeadm &>/dev/null; then
    echo "Installation de kubeadm, kubelet, kubectl..."
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
fi

echo "Rejoindre le cluster Kubernetes en tant que nœud control-plane avec les certificats..."
kubeadm join "$CONTROL_PLANE_ENDPOINT" \
    --token "$TOKEN" \
    --discovery-token-ca-cert-hash "$DISCOVERY_HASH" \
    --control-plane \
    --certificate-key "$CERTIFICATE_KEY"

echo "Le nœud a rejoint le cluster avec succès en tant que control-plane node."
echo "Pour interagir avec le cluster, utilisez l'admin.conf du premier master ou exportez le KUBECONFIG si vous l'avez récupéré."
