auth_url            = "https://10.0.2.15:5000/v3"
username            = "admin"
password            = "MSS5053ojTwjSGRBEgYSdH2vswXsNuIG"
project_name        = "admin"
project_domain_name = "Default"
user_domain_name    = "Default"
region              = "microstack"
insecure            = true
cacert_file         = "/var/snap/microstack/common/etc/ssl/certs/cacert.pem"

external_network_name = "external"
k8s_subnet_cidr       = "192.168.100.0/24"
k8s_pool_start        = "192.168.100.10"
k8s_pool_end          = "192.168.100.200"
pod_cidr              = "10.244.0.0/16"

image_name = "Ubuntu-22.04"
master_flavor = "m1.small"
worker_flavor = "m1.small"
public_key_path = "~/cloud-project/mykey.pub"
worker_count    = 2
master_ip = "192.168.100.20"
worker_ips      = ["192.168.100.11", "192.168.100.12"]
