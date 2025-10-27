Kind           = "service-resolver"
Name           = "service-response"
ConnectTimeout = "2s"
Failover = {
  "*" = {
    Targets = [
      {
        Service = "service-response"
        Peer = "peer1"
      }
    ]
  }
}