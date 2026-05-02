[Unit]
Description=DeployEx - Elixir/Erlang Release Manager
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=${deployex_home}
Environment="RELEASE_COOKIE=${release_cookie}"
Environment="RELEASE_NODE=${release_node}"
Environment="RELEASE_DISTRIBUTION=${release_distribution}"
Environment="DEPLOYEX_STORAGE_ADAPTER=${deployex_storage_adapter}"
Environment="AWS_REGION=${aws_region}"
Environment="S3_BUCKET=${s3_bucket}"
ExecStart=/usr/local/bin/deployex start
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
