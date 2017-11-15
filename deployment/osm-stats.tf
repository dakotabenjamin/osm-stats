provider "azurerm" {
}

variable "db_server_name" {
  type = "string"
  default = "osm-stats-postgresql"
}

variable "db_name" {
  type = "string"
  default = "osmstatsmm"
}

variable "db_user" {
  type = "string"
  default = "osmstatsmm"
}

resource "random_string" "db_password" {
  length = 16
}

resource "azurerm_resource_group" "osm-stats" {
  name = "osm-stats"
  location = "East US"
}

resource "azurerm_container_group" "osm-stats-api" {
  name = "osm-stats-api"
  location = "${azurerm_resource_group.osm-stats.location}"
  resource_group_name = "${azurerm_resource_group.osm-stats.name}"
  ip_address_type = "public"
  os_type = "linux"
  depends_on = ["azurerm_redis_cache.osm-stats", "azurerm_postgresql_database.osm-stats", "azurerm_postgresql_firewall_rule.osm-stats"]

  container {
    name = "osm-stats-api"
    image = "quay.io/americanredcross/osm-stats-api"
    cpu = "0.5"
    memory = "1.5"
    port = "80"

    environment_variables {
      PORT = "80"
      DATABASE_URL = "postgresql://${var.db_user}%40${var.db_server_name}:${random_string.db_password.result}@${azurerm_postgresql_server.osm-stats.fqdn}/${var.db_name}"
      FORGETTABLE_URL = "http://localhost:8080"
      REDIS_URL = "redis://:${urlencode(azurerm_redis_cache.osm-stats.primary_access_key)}@${azurerm_redis_cache.osm-stats.hostname}:${azurerm_redis_cache.osm-stats.port}/1"
    }
  }

  container {
    name = "forgettable"
    image = "quay.io/americanredcross/osm-stats-forgettable"
    cpu = "0.5"
    memory = "1.5"
    port = "8080"

    environment_variables {
      REDIS_URL = "redis://:${urlencode(azurerm_redis_cache.osm-stats.primary_access_key)}@${azurerm_redis_cache.osm-stats.hostname}:${azurerm_redis_cache.osm-stats.port}/1"
    }
  }
}

resource "azurerm_redis_cache" "osm-stats" {
  name = "osm-stats"
  location = "${azurerm_resource_group.osm-stats.location}"
  resource_group_name = "${azurerm_resource_group.osm-stats.name}"
  capacity = 0
  family = "C"
  sku_name = "Basic"
  enable_non_ssl_port = true

  redis_configuration {
  }
}

resource "azurerm_postgresql_server" "osm-stats" {
  name = "${var.db_server_name}"
  location = "${azurerm_resource_group.osm-stats.location}"
  resource_group_name = "${azurerm_resource_group.osm-stats.name}"

  sku {
    name = "PGSQLB50"
    capacity = 50
    tier = "Basic"
  }

  administrator_login = "${var.db_user}"
  administrator_login_password = "${random_string.db_password.result}"
  version = "9.6"
  storage_mb = "51200"
  # ssl_enforcement = "Enabled"
  ssl_enforcement = "Disabled"
}

resource "azurerm_postgresql_database" "osm-stats" {
  name = "${var.db_name}"
  resource_group_name = "${azurerm_resource_group.osm-stats.name}"
  server_name = "${azurerm_postgresql_server.osm-stats.name}"
  charset = "UTF8"
  collation = "English_United States.1252"
}

resource "azurerm_postgresql_firewall_rule" "osm-stats" {
  name = "public"
  resource_group_name = "${azurerm_resource_group.osm-stats.name}"
  server_name = "${azurerm_postgresql_server.osm-stats.name}"
  start_ip_address = "0.0.0.0"
  end_ip_address = "255.255.255.255"
}

output "redis_url" {
  value = "redis://:${urlencode(azurerm_redis_cache.osm-stats.primary_access_key)}@${azurerm_redis_cache.osm-stats.hostname}:${azurerm_redis_cache.osm-stats.port}/1"
}

output "database_url" {
  value = "postgresql://${var.db_user}%40${var.db_server_name}:${random_string.db_password.result}@${azurerm_postgresql_server.osm-stats.fqdn}/${var.db_name}"
}

output "api_url" {
  value = "http://${azurerm_container_group.osm-stats-api.ip_address}"
}

# az container show --name osm-stats-api --resource-group osm-stats-api
# az container logs --name osm-stats-api --resource-group osm-stats-api