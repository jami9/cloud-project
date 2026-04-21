# ============================================================
# outputs.tf
# ============================================================

output "master_floating_ip" {
  description = "Public IP of the master node"
  value       = openstack_networking_floatingip_v2.master.address
}

output "worker_floating_ips" {
  description = "Public IPs of worker nodes"
  value       = openstack_networking_floatingip_v2.worker[*].address
}

output "master_private_ip" {
  description = "Private IP of master node"
  value       = var.master_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = var.worker_ips
}

output "k8s_network_id" {
  description = "ID of the k8s private network"
  value       = openstack_networking_network_v2.k8s.id
}

output "k8s_subnet_id" {
  description = "ID of the k8s subnet"
  value       = openstack_networking_subnet_v2.k8s.id
}

output "k8s_router_id" {
  description = "ID of the k8s router"
  value       = openstack_networking_router_v2.k8s.id
}

output "security_group_id" {
  description = "ID of the k8s security group"
  value       = openstack_networking_secgroup_v2.k8s.id
}

output "ssh_master" {
  description = "SSH command to connect to master"
  value       = "ssh -i ~/cloud-project/mykey ubuntu@${openstack_networking_floatingip_v2.master.address}"
}

output "ssh_workers" {
  description = "SSH commands to connect to workers"
  value = [
    for i, ip in openstack_networking_floatingip_v2.worker[*].address :
    "ssh -i ~/cloud-project/mykey ubuntu@${ip}"
  ]
}
