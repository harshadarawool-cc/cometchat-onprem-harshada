terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state (recommended once the project has a state bucket). Local for now.
  # backend "gcs" {
  #   bucket = "onprem-499712-tfstate"
  #   prefix = "cometchat-rke2"
  # }
}
