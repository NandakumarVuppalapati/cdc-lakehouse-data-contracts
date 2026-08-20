# Mirrors the `postgres` service in docker-compose.yml — see that file's
# comments for why wal_level=logical / the two init scripts / the file-order
# convention (00- prefix runs before init.sql).

resource "docker_image" "postgres" {
  name = "postgres:16"
}

resource "docker_container" "postgres" {
  name    = "lakehouse-postgres"
  image   = docker_image.postgres.image_id
  command = ["postgres", "-c", "wal_level=logical", "-c", "max_wal_senders=10", "-c", "max_replication_slots=10"]

  env = [
    "POSTGRES_USER=lakehouse",
    "POSTGRES_PASSWORD=lakehouse",
    "POSTGRES_DB=sourcedb",
  ]

  ports {
    internal = 5432
    external = 5432
  }

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/postgres/00-create-nessie-db.sql"
    target    = "/docker-entrypoint-initdb.d/00-create-nessie-db.sql"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/postgres/00-create-apicurio-db.sql"
    target    = "/docker-entrypoint-initdb.d/00-create-apicurio-db.sql"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/postgres/init.sql"
    target    = "/docker-entrypoint-initdb.d/init.sql"
    read_only = true
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U lakehouse -d sourcedb"]
    interval = "5s"
    timeout  = "5s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 60
}
