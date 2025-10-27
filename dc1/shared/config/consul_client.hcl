data_dir = "/opt/consul/data"
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"
advertise_addr = "IP_ADDRESS"
retry_join = ["RETRY_JOIN"]
datacenter = "dc1"

acl {
  enabled = true
  tokens {
    agent = "e95b599e-166e-7d80-08ad-aee76e7ddf19"
  }
}

license_path = "/etc/consul.d/license.hclic"

log_level = "TRACE"

ports {
  http = 8500
  grpc_tls = 8502
}

encrypt = "aPuGh+5UDskRAbkLaXRzFoSOcSM+5vAK+NEYOWHJH7w="

tls {
  defaults {
    ca_file               = "/ops/shared/certs/consul-agent-ca.pem"
    cert_file             = "/ops/shared/certs/dc1-server-consul-0.pem"
    key_file              = "/ops/shared/certs/dc1-server-consul-0-key.pem"
    verify_incoming       = false
    verify_outgoing       = true
    verify_server_hostname = false
  }
  https = {
    "verify_incoming" = false
  }
  internal_rpc = {
    verify_incoming = false
    verify_server_hostname = false
  }
}

# Add telemetry configuration for metrics collection
telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = false
}

auto_encrypt {
  tls = true
}