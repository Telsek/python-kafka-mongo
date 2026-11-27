# KMS key Vault uses to unlock itself on startup (auto-unseal)
resource "aws_kms_key" "vault" {
  description             = "${var.project} Vault auto-unseal"
  enable_key_rotation     = true
  deletion_window_in_days = 7 # minimum AWS allows
}

# fixed name, so the Vault config in the GitOps repo never changes between applies
resource "aws_kms_alias" "vault" {
  name          = "alias/${var.project}-vault"
  target_key_id = aws_kms_key.vault.key_id
}

# IAM role the Vault pods get through Pod Identity - no AWS keys stored anywhere
resource "aws_iam_role" "vault" {
  name = "${var.project}-vault"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# only what auto-unseal needs, only on this key
resource "aws_iam_role_policy" "vault_kms" {
  name = "kms-unseal"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      Resource = aws_kms_key.vault.arn
    }]
  })
}

# links the role to Vault's service account (namespace "vault", name "vault" = Helm chart defaults)
resource "aws_eks_pod_identity_association" "vault" {
  cluster_name    = module.eks.cluster_name
  namespace       = "vault"
  service_account = "vault"
  role_arn        = aws_iam_role.vault.arn
}