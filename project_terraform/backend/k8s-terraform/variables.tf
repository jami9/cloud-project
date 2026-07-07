variable "auth_url"            { default = "" }
variable "username"            { default = "admin" }
variable "password"            { default = "keystone" }
variable "project_name"        { default = "admin" }
variable "project_domain_name" { default = "Default" }
variable "user_domain_name"    { default = "Default" }
variable "region"              { default = "microstack" }
variable "insecure"            { default = true }
variable "cacert_file"         { default = "" }

variable "external_network_name" { default = "external" }
variable "k8s_subnet_cidr"       { default = "192.168.100.0/24" }
variable "k8s_pool_start"        { default = "192.168.100.10" }
variable "k8s_pool_end"          { default = "192.168.100.200" }
variable "dns_nameservers"       { default = ["8.8.8.8", "1.1.1.1"] }

variable "master_image_name" { default = "migrated-k8s-master" }
variable "worker_image_name" { default = "migrated-k8s-worker1" }

variable "master_flavor" { default = "k8s.master" }
variable "worker_flavor" { default = "k8s.worker.large" }

variable "public_key_path" { default = "~/.ssh/id_rsa.pub" }

variable "worker_count" { default = 2 }
variable "master_ip"    { default = "192.168.100.20" }
variable "worker_ips"   { default = ["192.168.100.11", "192.168.100.12"] }

variable "pod_cidr"    { default = "10.244.0.0/16" }
variable "worker_ips_str" { default = "" }
variable "worker_image_name_2" { default = "migrated-k8s-worker2" }
