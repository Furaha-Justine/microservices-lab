output "eks_cluster_name"     { value = aws_eks_cluster.main.name }
output "eks_cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "eks_cluster_ca"       { value = aws_eks_cluster.main.certificate_authority[0].data }

output "rds_endpoint"        { value = aws_db_instance.main.address }
output "elasticache_address" { value = aws_elasticache_replication_group.main.primary_endpoint_address }

output "alb_controller_role_arn" { value = aws_iam_role.alb_controller.arn }
output "oidc_provider_arn"       { value = aws_iam_openid_connect_provider.eks.arn }

output "node_group_role_arn" { value = aws_iam_role.eks_nodes.arn }
output "rds_sg_id"           { value = aws_security_group.rds.id }
