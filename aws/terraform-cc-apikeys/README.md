# Using Terraform to Create and Distribute Confluent Cloud API Keys/Secrets

This example shows how to leverate both the Terraform Confluent Provider and the Terraform AWS Provider to create new Confluent API Keys for a Service Account and publish those new those new credentials into AWS's Secrets Manager.
Allowing for the use of the [CSID Secrets](https://github.com/confluentinc/csid-secrets-providers/tree/master/aws) Accelerator to fetch and inject those credentials into your Java Kafka Application.