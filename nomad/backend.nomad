job "backend" {
  datacenters = ["dc1"]

  group "backend" {
    count = 2

    network {
      port "http" {
        static = 8080
      }
    }

    task "backend" {
      driver = "docker"

      config {
        image = "themuffinman1/image-api:latest"
        command = "uv"
        args = ["run", "--no-dev", "gunicorn", "--workers", "4", "--bind", "0.0.0.0:8080", "image_api.web:app"]
        ports = ["http"]
      }

      env {
        CELERY_BROKER_URL     = "amqps://amontier:XXXX@rabbitmq.maurice-cloud.fr:5671/amontier"
        S3_ENDPOINT_URL       = "https://s3.eu-north-1.amazonaws.com"
        AWS_ACCESS_KEY_ID     = "XXXX"
        AWS_SECRET_ACCESS_KEY = "XXXX"
        S3_BUCKET_NAME        = "cloud-virt-mai-amontier-images"
        AWS_REGION_NAME       = "eu-north-1"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}