[Unit]
Description=DeployEx Release Manager
After=network.target
StartLimitInterval=120s
StartLimitBurst=3

[Service]
Type=exec
User=deploy
WorkingDirectory=${deployex_home}

Environment="DEPLOYEX_ADMIN_HASHED_PASSWORD=${deployex_admin_hash}"
Environment="RELEASE_NODE=${release_node}"
Environment="RELEASE_DISTRIBUTION=${release_distribution}"
Environment="RELEASE_COOKIE=${release_cookie}"
Environment="DEPLOYEX_STORAGE_ADAPTER=${deployex_storage_adapter}"
Environment="AWS_REGION=${aws_region}"
Environment="DEPLOYEX_S3_BUCKET=${s3_bucket}"

ExecStart=/usr/local/bin/deployex start

Restart=on-failure
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=deployex

[Install]
WantedBy=multi-user.target
