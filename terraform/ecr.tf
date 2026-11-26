# private image storage for our 2 apps - deleted on destroy, images included
resource "aws_ecr_repository" "app" {
  for_each = toset(["api", "client"])

  name                 = "${var.project}/${each.key}"
  force_delete         = true        # lets destroy remove repos that still have images
  image_tag_mutability = "IMMUTABLE" # a tag can never be overwritten

  image_scanning_configuration {
    scan_on_push = true # AWS checks every image for known vulnerabilities
  }
}

locals {
  app_dir = "${path.module}/.."

  # image tag = short fingerprint of the app's files
  # same code -> same tag (no rebuild), changed code -> new tag (rebuild + redeploy)
  image_tag = {
    for app in ["api", "client"] :
    app => substr(sha1(join("", [
      for f in sort(fileset("${local.app_dir}/${app}", "**")) :
      filesha1("${local.app_dir}/${app}/${f}")
    ])), 0, 10)
  }
}

# build + push each image during apply (runs on the machine running terraform)
resource "terraform_data" "image" {
  for_each = aws_ecr_repository.app

  # run again only if the repo is new or the code changed
  triggers_replace = [each.value.repository_url, local.image_tag[each.key]]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${split("/", each.value.repository_url)[0]}
      docker build --platform linux/amd64 -t ${each.value.repository_url}:${local.image_tag[each.key]} ${local.app_dir}/${each.key}
      docker push ${each.value.repository_url}:${local.image_tag[each.key]}
    EOT
  }
}