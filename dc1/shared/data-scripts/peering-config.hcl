Kind = "exported-services"
Name = "global"
Partition = "global"
Services = [
  {
    Name = "*"
    Namespace = "*"
    Consumers = [
      {
        Peer = "acceptor-cluster"
      }
    ]
  }
]
