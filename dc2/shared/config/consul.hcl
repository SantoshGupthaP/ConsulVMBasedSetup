data_dir = "/opt/consul/data"
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"
advertise_addr = "IP_ADDRESS"

bootstrap_expect = 3

datacenter = "dc2"

acl {
    enabled = true
    default_policy = "deny"
    tokens {
        initial_management = "e95b599e-166e-7d80-08ad-aee76e7ddf19"
        agent = "e95b599e-166e-7d80-08ad-aee76e7ddf19"
    }
    down_policy = "extend-cache"
    enable_token_persistence = true
    enable_token_replication = true
}

license_path = "/etc/consul.d/license.hclic"

log_level = "TRACE"

server = true
ui = true

retry_join = ["RETRY_JOIN"]

service {
    name = "jpmc-consul"
}

ports {
    http = 8500
    grpc_tls = 8502
}

connect {
    enabled = true
}
peering {
  enabled = true
}

encrypt = "aPuGh+5UDskRAbkLaXRzFoSOcSM+5vAK+NEYOWHJH7w="

tls {
    defaults {
        ca_file               = "/ops/shared/certs/consul-agent-ca.pem"
        cert_file             = "/ops/shared/certs/dc1-server-consul-0.pem"
        key_file              = "/ops/shared/certs/dc1-server-consul-0-key.pem"
        verify_incoming       = true
        verify_outgoing       = false
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
    allow_tls = true
}