terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.6"
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
}

# Resolve the latest Ubuntu 22.04 ARM64 image available for A1 Flex in this region
data "oci_core_images" "ubuntu_22_04_arm64" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

data "cloudinit_config" "chess_server" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "cloud-init.yaml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yaml", {
      erlang_version = var.erlang_version
      elixir_version = var.elixir_version
    })
  }
}

resource "oci_core_instance" "chess_server" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "chess-server"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_22_04_arm64.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.chess_public.id
    assign_public_ip = true
    display_name     = "chess-server-vnic"
    hostname_label   = "chess-server"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.chess_server.rendered
  }

  # Prevent accidental replacement of a live server
  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}
