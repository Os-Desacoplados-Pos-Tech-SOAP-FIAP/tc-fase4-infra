# Segredos compartilhados entre os serviços e a Lambda de autenticação.
#
# - JWT_SECRET: assina/valida o JWT HS256 de funcionários (OS) e de clientes (Lambda).
# - INTERNAL_SERVICE_TOKEN: header X-Internal-Token da rota interna do OS
#   (/api/os/internal/*), usada pela Lambda para buscar o cliente pelo CPF.
#
# Os valores são gerados aqui (random_password) e ficam no state do Terraform, que
# está em bucket S3 privado, versionado e criptografado. Nenhum valor é versionado.
locals {
  shared_secrets = {
    jwt            = "${var.cluster_name}/JWT_SECRET"
    internal_token = "${var.cluster_name}/INTERNAL_SERVICE_TOKEN"
  }
}

resource "random_password" "shared" {
  for_each = local.shared_secrets

  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "shared" {
  for_each = local.shared_secrets

  name = each.value
  # Sem janela de recuperação: o destroy/recriar dos ensaios não fica travado
  # pelo nome reservado durante os 7-30 dias padrão.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "shared" {
  for_each = local.shared_secrets

  secret_id     = aws_secretsmanager_secret.shared[each.key].id
  secret_string = random_password.shared[each.key].result
}
