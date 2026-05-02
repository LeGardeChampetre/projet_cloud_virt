job "frontend" {
  datacenters = ["dc1"]

  group "frontend" {
    count = 2

    network {
      port "http" {
        static = 3000
      }
    }

    task "frontend" {
      driver = "docker"

      config {
        image = "themuffinman1/image-web:latest"
        ports = ["http"]
	volumes = [
	  "local/config.json:/app/public/config.json"
	]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      template {
	data = <<EOF
{
  "endpoint" : "http://192.168.19.110"
}
EOF
	destination = "local/config.json"
      }
    }
  }
}
