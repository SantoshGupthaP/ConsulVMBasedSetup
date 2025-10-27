# Use command to generate the public private keys. 
# In principle, the Private key is used to sign the certs which only public can verify.

```sh
consul tls ca create
```

Output files
```
consul-agent-ca-key.pem
consul-agent-ca.pem
```


# Create certs now
```sh
consul tls cert create -server -dc dc1
```

Output files
```
dc1-server-consul-0-key.pem
dc1-server-consul-0.pem
```