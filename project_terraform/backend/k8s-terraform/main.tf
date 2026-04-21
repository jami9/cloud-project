# ============================================================
# main.tf — Kubernetes Cluster on MicroStack OpenStack
# ============================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "= 1.54.0"
    }
  }
}

# ============================================================
# Provider
# ============================================================
provider "openstack" {
  auth_url            = var.auth_url
  user_name           = var.username
  password            = var.password
  project_domain_name = var.project_domain_name
  user_domain_name    = var.user_domain_name
  tenant_name         = var.project_name
  region              = var.region
  insecure            = var.insecure
  cacert_file         = var.cacert_file
}

# ============================================================
# Data Sources — existing resources
# ============================================================
data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

# ============================================================
# Network: k8s-network + subnet
# ============================================================
resource "openstack_networking_network_v2" "k8s" {
  name           = "k8s-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "k8s" {
  name            = "k8s-subnet"
  network_id      = openstack_networking_network_v2.k8s.id
  cidr            = var.k8s_subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers

  allocation_pool {
    start = var.k8s_pool_start
    end   = var.k8s_pool_end
  }
}

# ============================================================
# Router: k8s-router (connected to external network)
# ============================================================
resource "openstack_networking_router_v2" "k8s" {
  name                = "k8s-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "k8s" {
  router_id = openstack_networking_router_v2.k8s.id
  subnet_id = openstack_networking_subnet_v2.k8s.id
}

# ============================================================
# Security Group: k8s-sg
# ============================================================
resource "openstack_networking_secgroup_v2" "k8s" {
  name        = "k8s-sg"
  description = "Security group for Kubernetes cluster nodes"
}

# --- SSH ---
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- Kubernetes API Server ---
resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- etcd ---
resource "openstack_networking_secgroup_rule_v2" "etcd" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2380
  remote_ip_prefix  = var.k8s_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- Kubelet API ---
resource "openstack_networking_secgroup_rule_v2" "kubelet" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = var.k8s_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- NodePort range ---
resource "openstack_networking_secgroup_rule_v2" "nodeport" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- Flannel / Calico overlay (VXLAN 8472) ---
resource "openstack_networking_secgroup_rule_v2" "flannel" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 8472
  port_range_max    = 8472
  remote_ip_prefix  = var.k8s_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- ICMP (ping) ---
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# --- All internal cluster traffic ---
resource "openstack_networking_secgroup_rule_v2" "internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.k8s_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# ============================================================
# Key Pair
# ============================================================
resource "openstack_compute_keypair_v2" "k8s" {
  name       = "k8s-keypair"
  public_key = file(var.public_key_path)
}

# ============================================================
# Master Node
# ============================================================
resource "openstack_networking_port_v2" "master" {
  name               = "k8s-master-port"
  network_id         = openstack_networking_network_v2.k8s.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.k8s.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = var.master_ip
  }
}

resource "openstack_compute_instance_v2" "master" {
  name            = "k8s-master"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.master_flavor
  key_pair        = openstack_compute_keypair_v2.k8s.name

  network {
    port = openstack_networking_port_v2.master.id
  }

  user_data = templatefile("${path.module}/cloud-init/master.yaml", {
    pod_cidr    = var.pod_cidr
    worker_ips  = var.worker_ips
  })

  metadata = {
    role = "master"
  }
}

resource "openstack_networking_floatingip_v2" "master" {
  pool = var.external_network_name
}

resource "openstack_compute_floatingip_associate_v2" "master" {
  floating_ip = openstack_networking_floatingip_v2.master.address
  instance_id = openstack_compute_instance_v2.master.id
}

# ============================================================
# Worker Nodes
# ============================================================
resource "openstack_networking_port_v2" "worker" {
  count              = var.worker_count
  name               = "k8s-worker${count.index + 1}-port"
  network_id         = openstack_networking_network_v2.k8s.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.k8s.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = var.worker_ips[count.index]
  }
}

resource "openstack_compute_instance_v2" "worker" {
  count           = var.worker_count
  name            = "k8s-worker${count.index + 1}"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.worker_flavor
  key_pair        = openstack_compute_keypair_v2.k8s.name

  network {
    port = openstack_networking_port_v2.worker[count.index].id
  }

  user_data = file("${path.module}/cloud-init/worker.yaml")

  metadata = {
    role = "worker"
  }
}

resource "openstack_networking_floatingip_v2" "worker" {
  count = var.worker_count
  pool  = var.external_network_name
}

resource "openstack_compute_floatingip_associate_v2" "worker" {
  count       = var.worker_count
  floating_ip = openstack_networking_floatingip_v2.worker[count.index].address
  instance_id = openstack_compute_instance_v2.worker[count.index].id
}
