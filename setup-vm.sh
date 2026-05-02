#!/bin/bash
set -e

VM_IP=$1  

if [ -z "$VM_IP" ]; then
  echo "Usage: bash setup-vm.sh <IP_DE_LA_VM>"
  exit 1
fi

echo "=== Mise à jour du système ==="
sudo apt update
sudo apt upgrade -y

echo "=== Installation Docker ==="
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker ubuntu

echo "=== Installation Consul et Nomad ==="
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y consul nomad

echo "=== Configuration Consul ==="
sudo tee /etc/consul.d/consul.hcl > /dev/null << EOF
data_dir         = "/opt/consul"
server           = true
bootstrap_expect = 3
bind_addr        = "0.0.0.0"
advertise_addr   = "$VM_IP"
client_addr      = "127.0.0.1"
retry_join       = ["192.168.19.101", "192.168.19.102", "192.168.19.103"]
encrypt          = "ukIlxspexewVh4z3ir0PBtbYXa5Hm8EOw/vWVd24WbM="
EOF

echo "=== Configuration Nomad ==="
sudo tee /etc/nomad.d/nomad.hcl > /dev/null << EOF
data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

advertise {
  http = "$VM_IP"
  rpc  = "$VM_IP"
  serf = "$VM_IP"
}

server {
  enabled          = true
  bootstrap_expect = 3
}

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
}
EOF

echo "=== Configuration service systemd Nomad ==="
# Crée le fichier service si absent, sinon corrige le chemin du binaire
if [ ! -f /etc/systemd/system/nomad.service ]; then
  sudo tee /etc/systemd/system/nomad.service > /dev/null << 'EOF'
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs/
Wants=network-online.target
After=network-online.target
Wants=consul.service
After=consul.service

[Service]
User=root
Group=root
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/bin/nomad agent -config /etc/nomad.d
KillMode=process
KillSignal=SIGINT
LimitNOFILE=65536
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
TasksMax=infinity
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF
else
  sudo sed -i 's|/usr/local/bin/nomad|/usr/bin/nomad|' /etc/systemd/system/nomad.service
  sudo sed -i 's/User=nomad/User=root/' /etc/systemd/system/nomad.service
  sudo sed -i 's/Group=nomad/Group=root/' /etc/systemd/system/nomad.service
fi

sudo systemctl daemon-reload
sudo systemctl enable consul nomad
sudo systemctl start consul

echo "=== Installation Nginx et Keepalived ===" #(VM1 et VM2 uniquement)
if [ "$VM_IP" = "192.168.19.101" ] || [ "$VM_IP" = "192.168.19.102" ]; then
  sudo apt install -y nginx keepalived

  # Config Nginx — load balancer vers les backends et frontends
  sudo tee /etc/nginx/sites-available/imgr > /dev/null << 'EOF'
upstream backend {
    server 192.168.19.101:8080;
    server 192.168.19.102:8080;
    server 192.168.19.103:8080;
}

upstream frontend {
    server 192.168.19.101:3000;
    server 192.168.19.102:3000;
    server 192.168.19.103:3000;
}

server {
    listen 80;

    # Requêtes API vers le pool de backends
    location /image {
        proxy_pass http://backend;
    }

    # Reste du trafic vers le frontend
    location / {
        proxy_pass http://frontend;
    }
}
EOF

  sudo ln -sf /etc/nginx/sites-available/imgr /etc/nginx/sites-enabled/imgr
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo systemctl enable nginx
  sudo systemctl restart nginx

  # Config Keepalived — MASTER sur VM1, BACKUP sur VM2
  if [ "$VM_IP" = "192.168.19.101" ]; then
    STATE="MASTER"
    PRIORITY=100
  else
    STATE="BACKUP"
    PRIORITY=50
  fi

  sudo tee /etc/keepalived/keepalived.conf > /dev/null << EOF
vrrp_instance VI_1 {
    state $STATE
    interface enp3s0
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass secret123
    }

    virtual_ipaddress {
        192.168.19.110
    }
}
EOF

  sudo systemctl enable keepalived
  sudo systemctl start keepalived
fi

echo ""
echo "Installation terminée pour $VM_IP"
echo ""
echo "Une fois ce script exécuté sur les 3 VMs, démarrer Nomad :"
echo "   sudo systemctl start nomad"
echo ""
echo "Puis déployer les jobs depuis n'importe quelle VM :"
echo "   nomad job run backend.nomad"
echo "   nomad job run worker.nomad"
echo "   nomad job run frontend.nomad"