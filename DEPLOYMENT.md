# Deployment on Fly.io

## Prerequisites

1. [Fly.io](https://fly.io) account
2. Fly.io CLI installed: `curl -L https://fly.io/install.sh | sh`
3. Authentication: `flyctl auth login`

## Configuration

### 1. Create the app on Fly.io

```bash
flyctl launch
```

This will:
- Ask for a unique name for the app (e.g., `chess-game`)
- Suggest a region
- Automatically detect and configure `fly.toml`

### 2. Customize `fly.toml` (after `flyctl launch`)

Edit `fly.toml` if you need to adjust:
- `app = "your-app-name"` → name of the created app
- `primary_region = "gig"` → region (e.g., `sjc`, `iad`, `fra`)
- `PHX_HOST` → update to the correct domain of your app

### 3. Generate the SECRET_KEY_BASE

Generate a secure secret key using Phoenix's generator command:

```bash
mix phx.gen.secret
```

This will output a random 64-character secret string. Copy this value for the next step.

### 4. Set environment variables

Set the secret key on Fly.io:

```bash
flyctl secrets set SECRET_KEY_BASE="<SECRET_KEY_BASE>"
```

### 5. Deploy

```bash
flyctl deploy
```

### 6. Check status

```bash
# View logs in real time
flyctl logs

# App status
flyctl status

# View configured environment variables
flyctl secrets list

# Open the app in the browser
flyctl open
```

## Troubleshooting

### Error: "Could not find App"
You need to run `flyctl launch` first to create the app:
```bash
flyctl launch
```

### Error: "SECRET_KEY_BASE is missing"
Configure the secret variable after creating the app:
```bash
flyctl secrets set SECRET_KEY_BASE="<SECRET_KEY_BASE>"
```

### App crashing or build error
Check the complete logs:
```bash
flyctl logs --all
```

### Rebuild without cache (forces Docker image rebuild)
```bash
flyctl deploy --build-only --no-cache
```

### Generate new SECRET_KEY_BASE
```bash
mix phx.gen.secret
```
Then configure on Fly.io:
```bash
flyctl secrets set SECRET_KEY_BASE="<new-key>"
```

## Next steps

After the initial deployment:
1. Configure a custom domain in the Fly.io dashboard
2. If you use a database, consider using PostgreSQL from Fly.io or Supabase
3. Monitor the app at [https://fly.io/dashboard](https://fly.io/dashboard)
