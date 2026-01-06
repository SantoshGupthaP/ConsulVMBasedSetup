#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

sudo apt-get update -y

# jq is required for load/stress test scripts, other tools are optional
sudo apt-get install -y unzip tree redis-tools jq curl tmux

# Install Go
GO_VERSION="1.21.5"
sudo rm -rf /usr/local/go
wget -O go.tar.gz https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go.tar.gz
rm go.tar.gz

export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc

# Set required environment variables for Go build
export HOME=/root
export GOCACHE=/root/.cache/go-build
export GOPATH=/root/go

mkdir -p /opt/app

cat << 'GO_SCRIPT' > /opt/app/main.go
package main

import (
    "fmt"
    "net/http"
    "os"
    "runtime"
    "time"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "text/plain")
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}

func main() {
    runtime.GOMAXPROCS(runtime.NumCPU())
    
    mux := http.NewServeMux()
    mux.HandleFunc("/health", healthHandler)
    mux.HandleFunc("/", healthHandler)
    
    server := &http.Server{
        Addr:              ":8080",
        Handler:           mux,
        ReadTimeout:       5 * time.Second,
        WriteTimeout:      10 * time.Second,
        IdleTimeout:       15 * time.Second,
        ReadHeaderTimeout: 2 * time.Second,
        MaxHeaderBytes:    1 << 20,
    }
    
    fmt.Printf("Starting Go health service on :8080 with %d CPUs\n", runtime.NumCPU())
    
    if err := server.ListenAndServe(); err != nil {
        fmt.Printf("Server failed to start: %v\n", err)
        os.Exit(1)
    }
}
GO_SCRIPT

cat << 'GO_MOD' > /opt/app/go.mod
module health-service

go 1.21
GO_MOD

# Build the Go application
cd /opt/app
echo "Building Go application..."
ls -la /opt/app/

# Verify Go is installed
/usr/local/go/bin/go version || {
    echo "Go not found! Checking installation..."
    ls -la /usr/local/go/bin/
    exit 1
}

# Build with verbose output
/usr/local/go/bin/go build -v -o health-service main.go || {
    echo "Go build failed!"
    exit 1
}

# Verify binary was created
if [ ! -f /opt/app/health-service ]; then
    echo "Binary not created!"
    ls -la /opt/app/
    exit 1
fi

# Ensure the binary is executable
chmod +x health-service
echo "Binary created successfully"
ls -la /opt/app/health-service

# Create systemd service
cat << 'SYSTEMD_SERVICE' | sudo tee /etc/systemd/system/health-service.service
[Unit]
Description=Health Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
ExecStart=/opt/app/health-service
Restart=always
RestartSec=5
StandardOutput=append:/opt/app/health-service.log
StandardError=append:/opt/app/health-service.log

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable health-service
sudo systemctl start health-service

# Wait a moment and verify it started
sleep 2
if sudo systemctl is-active --quiet health-service; then
    echo "Started Go health service via systemd"
    sudo systemctl status health-service
else
    echo "Failed to start Go health service"
    sudo systemctl status health-service
    sudo journalctl -u health-service -n 50
fi