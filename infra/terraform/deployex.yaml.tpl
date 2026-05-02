account_name: "prod"
hostname: "deployex"
port: 5001

release_adapter: "s3"
release_bucket: "${s3_bucket}"

secrets_adapter: "aws"
secrets_path: "${secrets_path}"
aws_region: "${aws_region}"

version: "0.9.0"
otp_version: 27
os_target: "ubuntu-24.04"

applications:
  - name: "chess"
    language: "elixir"
    replicas: 1
    replica_ports:
      - key: PORT
        base: 4000
    env:
      - key: AWS_REGION
        value: "${aws_region}"
