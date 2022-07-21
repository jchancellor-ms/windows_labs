sqladmin_password {
  value     = random_password.sqlpass.result
  sensitive = true
}