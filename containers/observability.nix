{ config, pkgs, ... }:

let
  # --- Declarative Configurations ---
  
  # 1. Prometheus Config
  prometheusConfig = pkgs.writeText "prometheus.yml" ''
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['127.0.0.1:9090']

      - job_name: 'node_exporter'
        static_configs:
          - targets: ['100.73.119.72:9100'] # Scrape host via Tailscale IP or use 127.0.0.1 if network=host

      - job_name: 'cadvisor'
        static_configs:
          - targets: ['127.0.0.1:8080']
  '';

  # 2. Loki Config
  lokiConfig = pkgs.writeText "loki.yaml" ''
    auth_enabled: false
    server:
      http_listen_port: 3100
    limits_config:
      allow_structured_metadata: false
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
  '';

  # 3. Promtail Config (Ships logs to Loki)
  promtailConfig = pkgs.writeText "promtail.yaml" ''
    server:
      http_listen_port: 9080
      grpc_listen_port: 0

    positions:
      filename: /tmp/positions.yaml

    clients:
      - url: http://127.0.0.1:3100/loki/api/v1/push

    scrape_configs:
      - job_name: system
        static_configs:
        - targets:
            - localhost
          labels:
            job: varlogs
            __path__: /var/log/*log
  '';

in {
  virtualisation.oci-containers.containers = {
    
    # --- GRAFANA ---
    grafana = {
      image = "grafana/grafana:latest";
      autoStart = true;
      extraOptions = [ "--network=host" ];
      ports = [ "3010:3000" ]; # Port 3000 is taken by Homepage
      volumes = [
        "grafana-storage:/var/lib/grafana"
      ];
      environment = {
        GF_SERVER_ROOT_URL = "https://grafana.tongatime.us";
        GF_SECURITY_ADMIN_USER = "admin";
        GF_SERVER_HTTP_ADDR = "0.0.0.0";
        GF_SERVER_HTTP_PORT = "3010";
        # Initial password, change immediately or use sops-nix to inject GF_SECURITY_ADMIN_PASSWORD
      };
    };

    # --- PROMETHEUS ---
    prometheus = {
      image = "prom/prometheus:latest";
      autoStart = true;
      extraOptions = [ "--network=host" ];
      ports = [ "9090:9090" ];
      volumes = [
        "${prometheusConfig}:/etc/prometheus/prometheus.yml:ro"
        "prometheus-data:/prometheus"
      ];
      cmd = [ "--config.file=/etc/prometheus/prometheus.yml" "--storage.tsdb.path=/prometheus" ];
    };

    # --- LOKI ---
    loki = {
      image = "grafana/loki:latest";
      autoStart = true;
      extraOptions = [ "--network=host" ];
      ports = [ "3100:3100" ];
      volumes = [
        "${lokiConfig}:/etc/loki/local-config.yaml:ro"
        "loki-data:/loki"
      ];
      cmd = [ "-config.file=/etc/loki/local-config.yaml" ];
    };

    # --- PROMTAIL ---
    promtail = {
      image = "grafana/promtail:latest";
      autoStart = true;
      extraOptions = [ "--network=host" ];
      ports = [ "9080:9080" ];
      volumes = [
        "${promtailConfig}:/etc/promtail/config.yml:ro"
        "/var/log:/var/log:ro" # Mount host logs
      ];
      cmd = [ "-config.file=/etc/promtail/config.yml" ];
    };

    # --- NODE EXPORTER ---
    node-exporter = {
      image = "prom/node-exporter:latest";
      autoStart = true;
      extraOptions = [ "--network=host" ];
      ports = [ "9100:9100" ];
      volumes = [
        "/proc:/host/proc:ro"
        "/sys:/host/sys:ro"
        "/:/rootfs:ro"
      ];
      cmd = [ 
        "--path.procfs=/host/proc" 
        "--path.sysfs=/host/sys"
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)"
      ];
    };
  };

  # Ensure permissions for mapped volumes if using host paths
  # (Since we are using named volumes above for data persistence, Podman handles this, 
  # but if you switch to host paths like /var/lib/grafana, uncomment the rules below)
  # systemd.tmpfiles.rules = [
  #   "d /var/lib/grafana 0755 472 472 - -" # 472 is Grafana uid
  # ];
}