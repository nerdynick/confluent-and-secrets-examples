# Define out 2 Providers Involved
terraform {
    required_providers {
        confluent = {
            source  = "confluentinc/confluent"
            version = "1.34.0"
        }
        aws = {
            source  = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

provider "aws" {
    region = "us-east-1"
}

provider "confluent" {
}

####
# Lets build out our ENV & Cluster.
# We'll keep it simple, fast, and cheap and create a Single Zone BASIC cluster for the Example.
# You can however create Multi-Zone and/or STANDARD or DEDICATED cluster types instead.
####
resource "confluent_environment" "prod" {
    display_name = "secrets-example"

    lifecycle {
        prevent_destroy = true
    }
}

resource "confluent_kafka_cluster" "basic" {
    display_name = "secrets-aws-example-cluster-1"
    availability = "SINGLE_ZONE"
    cloud        = "AWS"
    region       = "us-west-2"
    basic {}

    environment {
        id = confluent_environment.prod.id
    }

    lifecycle {
        prevent_destroy = true
    }
}


####
# Lets store our connection details as a secret.
# This make configuring our clients even easier.
# These are the Bootstrap Address and the REST Endpoint Address for the Kafka Cluster
####
resource "aws_secretsmanager_secret" "secrets-aws-example-cluster-1-bootstrap" {
    name = "secrets-aws-example-cluster-1-bootstrap"
}

resource "aws_secretsmanager_secret_version" "secrets-aws-example-cluster-1-bootstrap" {
    secret_id     = aws_secretsmanager_secret.secrets-aws-example-cluster-1-bootstrap.id
    secret_string = confluent_kafka_cluster.basic.bootstrap_endpoint
}

resource "aws_secretsmanager_secret" "secrets-aws-example-cluster-1-rest-endpoint" {
    name = "secrets-aws-example-cluster-1-rest-endpoint"
}

resource "aws_secretsmanager_secret_version" "secrets-aws-example-cluster-1-rest-endpoint" {
    secret_id     = aws_secretsmanager_secret.secrets-aws-example-cluster-1-rest-endpoint.id
    secret_string = confluent_kafka_cluster.basic.rest_endpoint
}

####
# Here's where we get into the real details for the example.
# We need to 1st have an Account to Create API Credentials for.
# In this case we are going to leverage a Service Account.
####
resource "confluent_service_account" "example-sa" {
    display_name = "secrets-aws-example-sa"
    description  = "Service Account for AWS Secrets Example"
}

resource "confluent_api_key" "kafka-api-key" {
    display_name = "secrets-aws-example-sa-apikey"
    description  = "Kafka API Key that is owned by 'secrets-aws-example-sa' service account"
    owner {
        id          = confluent_service_account.example-sa.id
        api_version = confluent_service_account.example-sa.api_version
        kind        = confluent_service_account.example-sa.kind
    }

    managed_resource {
        id          = confluent_kafka_cluster.basic.id
        api_version = confluent_kafka_cluster.basic.api_version
        kind        = confluent_kafka_cluster.basic.kind

        environment {
            id = confluent_environment.prod.id
        }
    }

    lifecycle {
        prevent_destroy = true
    }
}

####
# Lets store the newly crate Keys in our AWS Secrets Manager.
# We'll store both a JSON version and a JAAS version.
# The JSON version is useful for Non-Java Clients.
# The JAAS version is useful for leveraging the CSID Secrets Accelerator to provide credentials
####
resource "aws_secretsmanager_secret" "example-sa-apikey-json" {
    name = "example-sa-apikey-json"
}

resource "aws_secretsmanager_secret_version" "example-sa-apikey-json" {
    secret_id     = aws_secretsmanager_secret.example-sa-apikey-json.id
    secret_string = jsonencode(confluent_api_key.kafka-api-key)
}

resource "aws_secretsmanager_secret" "example-sa-apikey-jaas" {
    name = "example-sa-apikey-jaas"
}

resource "aws_secretsmanager_secret_version" "example-sa-apikey-jaas" {
    secret_id     = aws_secretsmanager_secret.example-sa-apikey-jaas.id
    secret_string = "org.apache.kafka.common.security.plain.PlainLoginModule required username='${confluent_api_key.kafka-api-key.id}' password='${confluent_api_key.kafka-api-key.secret}';"
}


####
# Lets create our Topic so we have something to Read/Write to.
# But 1st we need to give the SA access to create/write/read from the topic.
####

# Give our new SA the ability to manage the cluster. 
# So that we can create the ACLs for itself.
# This is more a work around for simplisity to re-use the same SA for the OPERATOR role and Topic Owner/Application Role.
resource "confluent_role_binding" "example-cluster-rb" {
    principal = "User:${confluent_service_account.example-sa.id}"
    role_name = "Operator"
    crn_pattern = "${confluent_kafka_cluster.basic.rbac_crn}"
}

resource "confluent_kafka_acl" "example-cluster-acls" {
    kafka_cluster {
        id = confluent_kafka_cluster.basic.id
    }
    resource_type = "CLUSTER"
    resource_name = "kafka-cluster"
    pattern_type  = "LITERAL"
    principal     = "User:${confluent_service_account.example-sa.id}"
    host          = "*"
    operation     = "ALL"
    permission    = "ALLOW"
    rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint

    credentials {
        key    = confluent_api_key.kafka-api-key.id
        secret = confluent_api_key.kafka-api-key.secret
    }

    lifecycle {
        prevent_destroy = true
    }
}



resource "confluent_kafka_topic" "example-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "secrets-example"
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.kafka-api-key.id
    secret = confluent_api_key.kafka-api-key.secret
  }

  lifecycle {
    prevent_destroy = true
  }
}