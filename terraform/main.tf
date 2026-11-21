terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

variable "project_id" {
  type        = string
  description = "GCP Project ID"
  default     = "kenya-one-505921"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "GCP zone"
  default     = "us-central1-a"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ----------------------------------------------------
# 1. Artifact Registry for Container Images
# ----------------------------------------------------
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "journal-repo"
  description   = "Docker repository for Journal API images"
  format        = "DOCKER"
}

# ----------------------------------------------------
# 2. VPC Network & Subnets
# ----------------------------------------------------
resource "google_compute_network" "k8s_vpc" {
  name                    = "journal-k8s-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name                     = "journal-k8s-subnet"
  ip_cidr_range            = "10.0.0.0/20"
  region                   = var.region
  network                  = google_compute_network.k8s_vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# ----------------------------------------------------
# 3. GKE Cluster
# ----------------------------------------------------
resource "google_service_account" "gke_sa" {
  account_id   = "journal-gke-node-sa"
  display_name = "GKE Node Service Account"
}

resource "google_project_iam_member" "gke_sa_node" {
  project = var.project_id
  role    = "roles/container.nodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_container_cluster" "primary" {
  name     = "journal-cluster"
  location = var.zone

  network    = google_compute_network.k8s_vpc.name
  subnetwork = google_compute_subnetwork.k8s_subnet.name

  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "journal-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 30
    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# ----------------------------------------------------
# 4. Cloud SQL Managed PostgreSQL Database
# ----------------------------------------------------
resource "google_compute_global_address" "private_ip_address" {
  name          = "journal-db-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.k8s_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.k8s_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "random_id" "db_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "postgres" {
  name             = "journal-pg-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region
  depends_on       = [google_service_networking_connection.private_vpc_connection]

  deletion_protection = false

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.k8s_vpc.id
      enable_private_path_for_google_cloud_services = true
    }
  }
}

resource "google_sql_database" "database" {
  name     = "career_journal"
  instance = google_sql_database_instance.postgres.name
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "google_sql_user" "users" {
  name     = "journaluser"
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}

# ----------------------------------------------------
# 5. Static External IP for Public Ingress
# ----------------------------------------------------
resource "google_compute_global_address" "ingress_ip" {
  name = "journal-ingress-ip"
}

# ----------------------------------------------------
# 6. Service Account for CI/CD Deployment
# ----------------------------------------------------
resource "google_service_account" "ci_deployer" {
  account_id   = "journal-ci-deployer"
  display_name = "GitHub Actions CI/CD Deployer"
}

resource "google_project_iam_member" "ci_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.ci_deployer.email}"
}

resource "google_project_iam_member" "ci_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.ci_deployer.email}"
}

resource "google_service_account_key" "ci_key" {
  service_account_id = google_service_account.ci_deployer.name
}

# ----------------------------------------------------
# Outputs
# ----------------------------------------------------
output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gke_cluster_zone" {
  value = google_container_cluster.primary.location
}

output "db_private_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "ingress_ip" {
  value = google_compute_global_address.ingress_ip.address
}

output "ci_service_account_key" {
  value     = google_service_account_key.ci_key.private_key
  sensitive = true
}
