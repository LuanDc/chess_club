# Task 06: nginx Reverse Proxy and TLS

> RFC reference: §8.3 — nginx
> Depends on: Task 01 (VM must be running), Task 05 (chess app must be listening on :4000, DeployEx on :5001)

## Goal

Configure nginx as the public-facing reverse proxy with TLS termination via Let's Encrypt. After this task, the chess application is reachable at a public HTTPS URL with a valid, auto-renewing certificate. Phoenix LiveView WebSocket connections must work through the proxy, which requires specific upgrade headers.

## Checklist

- [ ] Point a domain name (e.g. `chess.example.com`) at the VM's public IP via an A record
- [ ] Wait for DNS propagation and verify: `dig chess.example.com` resolves to the VM IP
- [ ] SSH into the VM
- [ ] Install nginx: `sudo apt install nginx`
- [ ] Install Certbot and the nginx plugin: `sudo apt install certbot python3-certbot-nginx`
- [ ] Obtain a Let's Encrypt TLS certificate:
  - [ ] `sudo certbot --nginx -d chess.example.com`
  - [ ] Certbot auto-configures nginx with the certificate paths
- [ ] Edit the nginx config (`/etc/nginx/sites-available/chess`) to add the full server blocks:
  - [ ] HTTPS server block (:443):
    - [ ] `proxy_pass http://127.0.0.1:4000` for `location /` with WebSocket upgrade headers
    - [ ] `proxy_pass http://127.0.0.1:5001` for `location /deployex/`
    - [ ] `proxy_http_version 1.1`
    - [ ] `proxy_set_header Upgrade $http_upgrade`
    - [ ] `proxy_set_header Connection "upgrade"`
    - [ ] `proxy_set_header Host $host`
    - [ ] `proxy_set_header X-Real-IP $remote_addr`
  - [ ] HTTP server block (:80): `return 301 https://$host$request_uri`
- [ ] Enable the site config: `sudo ln -s /etc/nginx/sites-available/chess /etc/nginx/sites-enabled/`
- [ ] Test the nginx configuration: `sudo nginx -t`
- [ ] Reload nginx: `sudo systemctl reload nginx`
- [ ] Verify HTTPS works in a browser: navigate to `https://chess.example.com`
  - [ ] TLS certificate is valid (no browser warning)
  - [ ] Chess application loads
- [ ] Verify Phoenix LiveView WebSocket connections work:
  - [ ] Open the chess app in a browser
  - [ ] Start or join a game; confirm the board is interactive (LiveView is connected)
  - [ ] Check browser DevTools → Network → WS for an active WebSocket connection
- [ ] Verify HTTP redirects to HTTPS: `curl -I http://chess.example.com` returns 301
- [ ] Verify Certbot auto-renewal is active:
  - [ ] `sudo systemctl status certbot.timer`
  - [ ] Run a dry-run renewal: `sudo certbot renew --dry-run`

## Notes / References

- Certbot auto-configures `ssl_certificate` and `ssl_certificate_key` paths in nginx; do not overwrite them manually
- WebSocket upgrade headers are essential for Phoenix LiveView — without them, the LiveView connection silently fails
- The DeployEx dashboard at `/deployex/` should ideally have an IP allowlist in nginx for security (see RFC §11)
- Certbot systemd timer fires twice daily by default; certificates renew when less than 30 days remain
- If using Oracle Cloud's firewall in addition to the OS-level iptables, ensure ports 80 and 443 are also open in the OCI Network Security Group or Security List
