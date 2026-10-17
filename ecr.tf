# Um repositório de imagens por serviço, publicado pelo CD de cada repo
# (tc-fase4-<servico>). O nome deriva de var.cluster_name: oficina-fase4-os,
# oficina-fase4-catalog, oficina-fase4-billing e oficina-fase4-execution.
locals {
  ecr_services = toset(["os", "catalog", "billing", "execution"])
}

resource "aws_ecr_repository" "service" {
  for_each = local.ecr_services

  name                 = "${var.cluster_name}-${each.key}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  # Ambiente de estudo: permite destroy mesmo com imagens no repositório.
  force_delete = true
}

# Mantém só as 10 imagens mais recentes de cada serviço (custo de storage).
resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantem as 10 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
