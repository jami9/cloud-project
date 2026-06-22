output "master_floating_ip" {
  value = openstack_networking_floatingip_v2.master.address
}
output "ssh_master" {
  value = "ssh -i ~/.ssh/id_rsa user1@${openstack_networking_floatingip_v2.master.address}"
}

output "worker1_floating_ip" {
  value = openstack_networking_floatingip_v2.worker1.address
}
output "ssh_worker1" {
  value = "ssh -i ~/.ssh/id_rsa user2@${openstack_networking_floatingip_v2.worker1.address}"
}

output "worker2_floating_ip" {
  value = openstack_networking_floatingip_v2.worker2.address
}
output "ssh_worker2" {
  value = "ssh -i ~/.ssh/id_rsa user3@${openstack_networking_floatingip_v2.worker2.address}"
}
