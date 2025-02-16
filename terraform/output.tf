output "cluster_id" {
  value = aws_eks_cluster.ibtisamx.id
}

output "node_group_id" {
  value = aws_eks_node_group.ibtisamx.id
}

output "vpc_id" {
  value = aws_vpc.ibtisamx_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.ibtisamx_subnet[*].id
}
