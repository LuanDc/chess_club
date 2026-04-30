resource "oci_core_vcn" "chess" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "chess-vcn"
  dns_label      = "chessvn"
}

resource "oci_core_internet_gateway" "chess" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.chess.id
  display_name   = "chess-igw"
  enabled        = true
}

resource "oci_core_route_table" "chess" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.chess.id
  display_name   = "chess-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.chess.id
  }
}

resource "oci_core_security_list" "chess" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.chess.id
  display_name   = "chess-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_subnet" "chess_public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.chess.id
  cidr_block        = var.subnet_cidr
  display_name      = "chess-public-subnet"
  dns_label         = "chesspub"
  route_table_id    = oci_core_route_table.chess.id
  security_list_ids = [oci_core_security_list.chess.id]
}
