output "app_ip_address" {
  value = aws_eip.app.public_ip
}

output "db_admin_username" {
  value = aws_db_instance.example.username
}

output "db_admin_password" {
  sensitive = true
  value     = aws_db_instance.example.password
}

output "db_address" {
  value       = aws_db_instance.example.address
  description = "NB this is here just for reference. you can only access this address inside the vpc network."
}
