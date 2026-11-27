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

# --- bootstrap Job: sets up a fresh Vault, keeps its root token in SSM ---

# placeholders - the Job writes the real values, Terraform deletes them on destroy
resource "aws_ssm_parameter" "vault_root_token" {
  name   = "/${var.project}/vault/root-token"
  type   = "SecureString"
  key_id = aws_kms_alias.vault.name
  value  = "set-by-bootstrap-job"

  lifecycle {
    ignore_changes = [value] # the Job owns the value
  }
}

# full init output (root token + recovery key) - needed only for disaster recovery
resource "aws_ssm_parameter" "vault_init" {
  name   = "/${var.project}/vault/init"
  type   = "SecureString"
  key_id = aws_kms_alias.vault.name
  value  = "set-by-bootstrap-job"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_role" "vault_bootstrap" {
  name = "${var.project}-vault-bootstrap"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# read/write only these 2 parameters, encrypt/decrypt only with the Vault key
resource "aws_iam_role_policy" "vault_bootstrap" {
  name = "ssm-vault-params"
  role = aws_iam_role.vault_bootstrap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = [aws_ssm_parameter.vault_root_token.arn, aws_ssm_parameter.vault_init.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt"]
        Resource = aws_kms_key.vault.arn
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "vault_bootstrap" {
  cluster_name    = module.eks.cluster_name
  namespace       = "vault"
  service_account = "vault-bootstrap"
  role_arn        = aws_iam_role.vault_bootstrap.arn
}