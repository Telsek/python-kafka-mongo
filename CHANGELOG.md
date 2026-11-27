# Changelog

## [1.1.0](https://github.com/Telsek/python-kafka-mongo/compare/v1.0.0...v1.1.0) (2026-11-27)


### Features

* **api:** health check watches the Kafka reader ([#3](https://github.com/Telsek/python-kafka-mongo/issues/3)) ([73a0559](https://github.com/Telsek/python-kafka-mongo/commit/73a055995206692238450d8a61b6dd426010bc93))

## 1.0.0 (2026-11-27)


### Features

* 3-AZ VPC with private subnets and NAT ([bea821c](https://github.com/Telsek/python-kafka-mongo/commit/bea821c807e65b077e0877f7f06c06e4965a5078))
* ArgoCD with root app pointing at the GitOps repo ([ad1e595](https://github.com/Telsek/python-kafka-mongo/commit/ad1e59514c9ed823bdb965a410b306f338a86c40))
* AWS Load Balancer Controller and ExternalDNS ([399d1de](https://github.com/Telsek/python-kafka-mongo/commit/399d1de75c9c0eae1134934422d853cd8ea45a47))
* EKS cluster with managed node group and EBS CSI ([a02ab70](https://github.com/Telsek/python-kafka-mongo/commit/a02ab7056ce68917bdfb470ae19b53d3c2b9bde0))
* KMS key and Pod Identity role for Vault auto-unseal ([8a6a0cd](https://github.com/Telsek/python-kafka-mongo/commit/8a6a0cd6b44ee49169c2bb3d6a8e61f6e6e32088))
* move from ECS to EKS ([c8d5e49](https://github.com/Telsek/python-kafka-mongo/commit/c8d5e49576d25e1bc2838899c85b84081a34b580))
* one-command teardown ([bbee298](https://github.com/Telsek/python-kafka-mongo/commit/bbee2984932630a0c93aec6c4ab270edefd77fe2))
* OpenTelemetry auto-tracing (export off locally, on in the cluster) ([8366b9e](https://github.com/Telsek/python-kafka-mongo/commit/8366b9ecfe2cbd5b38bebb1f184ad4b30ea432b4))
* SSM parameters and IAM role for the Vault bootstrap Job ([5b7534c](https://github.com/Telsek/python-kafka-mongo/commit/5b7534ca8dbd21b69bb62a5c0e417f0313f4b887))


### Bug Fixes

* commit Kafka offsets after Mongo save, producer acks=all ([1cc74c1](https://github.com/Telsek/python-kafka-mongo/commit/1cc74c19dee221027cf9b683a3752424999ac048))
* drop pip from images and apply Debian updates (Trivy HIGH findings) ([7f72cb9](https://github.com/Telsek/python-kafka-mongo/commit/7f72cb9054571023e0a540717f5f28cb9bcd1d17))
* pin api versions, destroy ArgoCD before the LB controller ([8629b17](https://github.com/Telsek/python-kafka-mongo/commit/8629b1789e50240169b7673e87057ae63724bdc4))
* pin node image - MongoDB 8.0 breaks on kernel 6.19+ ([3e0d0f9](https://github.com/Telsek/python-kafka-mongo/commit/3e0d0f93f5ca348fb261fbcd241a03214e119203))
