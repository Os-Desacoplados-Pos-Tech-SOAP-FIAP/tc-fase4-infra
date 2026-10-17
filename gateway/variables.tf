variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos."
  type        = string
  default     = "oficina-fase4"
}

variable "state_bucket" {
  description = "Bucket S3 com os states das stacks da Fase 4 (infra e auth)."
  type        = string
  default     = "tc-fase4-tfstate-538880133939"
}
