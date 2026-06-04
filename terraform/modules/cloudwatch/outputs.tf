output "cluster_log_group" {
  value = aws_cloudwatch_log_group.eks_cluster.name
}

output "app_log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "cloudwatch_agent_role_arn" {
  value = aws_iam_role.cloudwatch_agent.arn
}
