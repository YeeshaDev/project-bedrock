output "dev_user_arn" {
  value = aws_iam_user.dev_view.arn
}

output "dev_user_access_key_id" {
  value     = aws_iam_access_key.dev_view.id
  sensitive = true
}

output "dev_user_secret_key" {
  value     = aws_iam_access_key.dev_view.secret
  sensitive = true
}

output "dev_user_password" {
  value     = aws_iam_user_login_profile.dev_view.password
  sensitive = true
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "cart_irsa_role_arn" {
  value = aws_iam_role.cart_irsa.arn
}
