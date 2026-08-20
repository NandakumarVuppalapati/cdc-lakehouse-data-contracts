# Mirrors the marquez-db/marquez-api/marquez-web services in
# docker-compose.yml — see ADR 0025 for the version pin, health-endpoint
# source, and port choices.

resource "docker_image" "marquez_db" {
  name = "postgres:14"
}

resource "docker_container" "marquez_db" {
  name  = "lakehouse-marquez-db"
  image = docker_image.marquez_db.image_id

  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=password",
    "MARQUEZ_DB=marquez",
    "MARQUEZ_USER=marquez",
    "MARQUEZ_PASSWORD=marquez",
  ]

  ports {
    internal = 5432
    external = 5433
  }

  volumes {
    volume_name    = docker_volume.marquez_db_data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U postgres"]
    interval = "5s"
    timeout  = "5s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 60
}

resource "docker_image" "marquez_api" {
  name = "marquezproject/marquez:0.51.1"
}

resource "docker_container" "marquez_api" {
  name  = "lakehouse-marquez-api"
  image = docker_image.marquez_api.image_id

  env = [
    "MARQUEZ_PORT=5000",
    "MARQUEZ_ADMIN_PORT=5001",
    "POSTGRES_HOST=marquez-db",
    "POSTGRES_PORT=5432",
    "SEARCH_ENABLED=false",
  ]

  ports {
    internal = 5000
    external = 5000
  }
  ports {
    internal = 5001
    external = 5001
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -qO- http://localhost:5001/healthcheck || exit 1"]
    interval = "10s"
    timeout  = "10s"
    retries  = 15
  }

  wait         = true
  wait_timeout = 90

  depends_on = [docker_container.marquez_db]
}

resource "docker_image" "marquez_web" {
  name = "marquezproject/marquez-web:0.51.1"
}

resource "docker_container" "marquez_web" {
  name  = "lakehouse-marquez-web"
  image = docker_image.marquez_web.image_id

  env = [
    "MARQUEZ_HOST=marquez-api",
    "MARQUEZ_PORT=5000",
    "WEB_PORT=3000",
    "REACT_APP_ADVANCED_SEARCH=false",
  ]

  ports {
    internal = 3000
    external = 3002
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [docker_container.marquez_api]
}
