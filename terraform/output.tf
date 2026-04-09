output "cluster_id" {
  value = aws_eks_cluster.ibtisamiq.id
}

output "node_group_id" {
  value = aws_eks_node_group.ibtisamiq.id
}

output "vpc_id" {
  value = aws_vpc.ibtisamiq_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.ibtisamiq_subnet[*].id
}
