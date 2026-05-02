job "worker" {
  datacenters = ["dc1"]

  group "worker" {
    count = 2

    task "worker" {
      driver = "docker"

      config {
        image   = "themuffinman1/image-api:latest"
        command = "uv"
        args    = ["run", "--no-dev", "celery", "--app", "image_api.worker.app", "worker"]
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
        cpu    = 500
        memory = 512
      }
    }
  }
}