# ============================================================
# variables.tf
# ============================================================

# ---- OpenStack Auth ----
variable "auth_url" {
  description = "Keystone auth URL"
  type        = string
  default     = "https://10.0.2.15:5000/v3"
}

variable "username" {
  description = "OpenStack username"
  type        = string
  default     = "user_terraform"
}

variable "password" {
  description = "OpenStack password"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "OpenStack project (tenant) name"
  type        = string
  default     = "k8s_terraform"
}

variable "project_domain_name" {
  description = "Project domain"
  type        = string
  default     = "Default"
}

variable "user_domain_name" {
  description = "User domain"
  type        = string
  default     = "Default"
}

variable "region" {
  description = "OpenStack region"
  type        = string
  default     = "microstack"
}

variable "insecure" {
  description = "Skip TLS verification (MicroStack self-signed cert)"
  type        = bool
  default     = true
}

variable "cacert_file" {
  description = "Path to CA cert (optional if insecure = true)"
  type        = string
  default     = "/var/snap/microstack/common/etc/ssl/certs/cacert.pem"
}

# ---- Network ----
variable "external_network_name" {
  description = "Name of existing external network"
  type        = string
  default     = "external"
}

variable "k8s_subnet_cidr" {
  description = "CIDR for the k8s private subnet"
  type        = string
  default     = "192.168.100.0/24"
}

variable "k8s_pool_start" {
  description = "Start of DHCP pool"
  type        = string
  default     = "192.168.100.10"
}

variable "k8s_pool_end" {
  description = "End of DHCP pool"
  type        = string
  default     = "192.168.100.200"
}

variable "dns_nameservers" {
  description = "DNS servers for the subnet"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "pod_cidr" {
  description = "CIDR used by the CNI plugin (Flannel default)"
  type        = string
  default     = "10.244.0.0/16"
}

# ---- Compute ----
variable "image_name" {
  description = "Glance image name (Ubuntu 22.04 recommended)"
  type        = string
  default     = "ubuntu-22.04"
}

variable "master_flavor" {
  description = "Flavor for master node (min 2 vCPU / 4 GB)"
  type        = string
  default     = "m1.small"
}

variable "worker_flavor" {
  description = "Flavor for worker nodes (min 2 vCPU / 4 GB)"
  type        = string
  default     = "m1.small"
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "master_ip" {
  description = "Fixed IP for master (must be in k8s_subnet_cidr)"
  type        = string
  default     = "192.168.100.10"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_ips" {
  description = "Fixed IPs for workers (list length must match worker_count)"
  type        = list(string)
  default     = ["192.168.100.11", "192.168.100.12"]
}
