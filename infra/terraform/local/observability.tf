# Mirrors the prometheus/pushgateway/kafka-exporter/grafana services in
# docker-compose.yml. See ADR 0024, and ADR 0025 for the pushgateway
# host-port fix (9096, not 9091 — a real collision with apicurio's admin
# port, caught while adding Marquez in this same session).

resource "docker_image" "prometheus" {
  name = "prom/prometheus:v3.13.2"
}

resource "docker_container" "prometheus" {
  name  = "lakehouse-prometheus"
  image = docker_image.prometheus.image_id

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/observability/prometheus/prometheus.yml"
    target    = "/etc/prometheus/prometheus.yml"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }

  ports {
    internal = 9090
    external = 9090
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -qO- http://localhost:9090/-/ready || exit 1"]
    interval = "10s"
    timeout  = "5s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 60
}

resource "docker_image" "pushgateway" {
  name = "prom/pushgateway:v1.11.3"
}

resource "docker_container" "pushgateway" {
  name  = "lakehouse-pushgateway"
  image = docker_image.pushgateway.image_id

  ports {
    internal = 9091
    external = 9096
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }
}

resource "docker_image" "kafka_exporter" {
  name = "danielqsj/kafka-exporter:v1.9.0"
}

resource "docker_container" "kafka_exporter" {
  name = "lakehouse-kafka-exporter"
  image = docker_image.kafka_exporter.image_id
  command = [
    "--kafka.server=kafka:29092",
    "--group.filter=connect-shop-.*",
    "--topic.filter=shop\\..*",
  ]

  ports {
    internal = 9308
    external = 9308
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [docker_container.kafka]
}

resource "docker_image" "grafana" {
  name = "grafana/grafana:12.4.8"
}

resource "docker_container" "grafana" {
  name  = "lakehouse-grafana"
  image = docker_image.grafana.image_id

  env = [
    "GF_AUTH_ANONYMOUS_ENABLED=true",
    "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer",
  ]

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/observability/grafana/provisioning/datasources"
    target    = "/etc/grafana/provisioning/datasources"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/observability/grafana/provisioning/dashboards"
    target    = "/etc/grafana/provisioning/dashboards"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/observability/grafana/dashboards"
    target    = "/etc/grafana/provisioning/dashboards/files"
    read_only = true
  }

  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
  }

  ports {
    internal = 3000
    external = 3001
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [docker_container.prometheus]
}
