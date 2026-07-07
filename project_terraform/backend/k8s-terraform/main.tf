terraform {
  required_version = ">= 1.3.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "= 1.54.0"
    }
  }
}

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

data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

data "openstack_images_image_v2" "master" {
  name        = "migrated-k8s-master"
  most_recent = true
}

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

resource "openstack_networking_router_v2" "k8s" {
  name                = "k8s-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "k8s" {
  router_id = openstack_networking_router_v2.k8s.id
  subnet_id = openstack_networking_subnet_v2.k8s.id
}

resource "openstack_networking_secgroup_v2" "k8s" {
  name        = "k8s-sg"
  description = "Security group Kubernetes"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.k8s_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "nodeport" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "prometheus" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9090
  port_range_max    = 9090
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "grafana" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3000
  port_range_max    = 3000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_compute_keypair_v2" "k8s" {
  name       = "k8s-keypair"
  public_key = file(pathexpand(var.public_key_path))
}

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
  name        = "k8s-master"
  image_id    = data.openstack_images_image_v2.master.id
  flavor_name = "k8s.master"
  key_pair    = openstack_compute_keypair_v2.k8s.name
  network {
    port = openstack_networking_port_v2.master.id
  }
  metadata = { role = "master" }
}

resource "openstack_networking_floatingip_v2" "master" {
  pool = var.external_network_name
}

resource "openstack_compute_floatingip_associate_v2" "master" {
  floating_ip = openstack_networking_floatingip_v2.master.address
  instance_id = openstack_compute_instance_v2.master.id
}

# ── Worker 1 ──────────────────────────────────────────────────
data "openstack_images_image_v2" "worker1" {
  name        = "migrated-k8s-worker1"
  most_recent = true
}

resource "openstack_networking_port_v2" "worker1" {
  name               = "k8s-worker1-port"
  network_id         = openstack_networking_network_v2.k8s.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.k8s.id]
  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = var.worker_ips[0]
  }
}

resource "openstack_compute_instance_v2" "worker1" {
  name        = "k8s-worker1"
  image_id    = data.openstack_images_image_v2.worker1.id
  flavor_name = "k8s.worker"
  key_pair    = openstack_compute_keypair_v2.k8s.name
  network {
    port = openstack_networking_port_v2.worker1.id
  }
  metadata = { role = "worker" }
}

resource "openstack_networking_floatingip_v2" "worker1" {
  pool = var.external_network_name
}

resource "openstack_compute_floatingip_associate_v2" "worker1" {
  floating_ip = openstack_networking_floatingip_v2.worker1.address
  instance_id = openstack_compute_instance_v2.worker1.id
}

# ── Worker 2 ──────────────────────────────────────────────────
data "openstack_images_image_v2" "worker2" {
  name        = var.worker_image_name_2
  most_recent = true
}
resource "openstack_networking_port_v2" "worker2" {
  name               = "k8s-worker2-port"
  network_id         = openstack_networking_network_v2.k8s.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.k8s.id]
  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = var.worker_ips[1]
  }
}

resource "openstack_compute_instance_v2" "worker2" {
  name        = "k8s-worker2"
  image_id    = data.openstack_images_image_v2.worker2.id
  flavor_name = "k8s.worker"
  key_pair    = openstack_compute_keypair_v2.k8s.name
  network {
    port = openstack_networking_port_v2.worker2.id
  }
  metadata = { role = "worker" }
}

resource "openstack_networking_floatingip_v2" "worker2" {
  pool = var.external_network_name
}

resource "openstack_compute_floatingip_associate_v2" "worker2" {
  floating_ip = openstack_networking_floatingip_v2.worker2.address
  instance_id = openstack_compute_instance_v2.worker2.id
}
