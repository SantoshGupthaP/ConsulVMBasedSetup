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

# Build and start the Go application
cd /opt/app
/usr/local/go/bin/go build -o health-service main.go

# Ensure the binary is executable
chmod +x health-service

# Start the service in background
nohup ./health-service > /opt/app/health-service.log 2>&1 &
PID=$!

# Wait a moment and verify it started
sleep 2
if kill -0 $PID 2>/dev/null; then
    echo "Started Go health service with PID $PID"
else
    echo "Failed to start Go health service"
    cat /opt/app/health-service.log
    exit 1
fi