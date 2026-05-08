# Deployment no Fly.io

## Pré-requisitos

1. Conta no [Fly.io](https://fly.io)
2. CLI do Fly.io instalada: `curl -L https://fly.io/install.sh | sh`
3. Autenticação: `flyctl auth login`

## Configuração

### 1. Criar a app no Fly.io

```bash
flyctl launch
```

Isso vai:
- Pedir um nome único para a app (ex: `chess-game`)
- Sugerir uma região
- Detectar e configurar automaticamente o `fly.toml`

### 2. Customizar o `fly.toml` (após `flyctl launch`)

Edite `fly.toml` se precisar ajustar:
- `app = "seu-app-name"` → nome da app criada
- `primary_region = "gig"` → região (ex: `sjc`, `iad`, `fra`)
- `PHX_HOST` → atualize para o domínio correto da sua app

### 3. Configurar variáveis de ambiente

Defina a chave secreta no Fly.io:

```bash
flyctl secrets set SECRET_KEY_BASE="<SECRET_KEY_BASE>"
```

### 4. Deploy

```bash
flyctl deploy
```

### 5. Verificar o status

```bash
# Ver logs em tempo real
flyctl logs

# Status da app
flyctl status

# Ver variáveis de ambiente configuradas
flyctl secrets list

# Abrir a app no navegador
flyctl open
```

## Troubleshooting

### Erro: "Could not find App"
Você precisa rodar `flyctl launch` primeiro para criar a app:
```bash
flyctl launch
```

### Erro: "SECRET_KEY_BASE is missing"
Configure a variável secreta após criar a app:
```bash
flyctl secrets set SECRET_KEY_BASE="SI7z15iMKSzzJZG0HEIo41tonKEsJQHoEzCQtfRfrRoyW7nsUvqabnmC2ZkWc4qa"
```

### App crashing ou erro no build
Verifique os logs completos:
```bash
flyctl logs --all
```

### Rebuild sem cache (força rebuild da imagem Docker)
```bash
flyctl deploy --build-only --no-cache
```

### Gerar nova SECRET_KEY_BASE
```bash
mix phx.gen.secret
```
Depois configure no Fly.io:
```bash
flyctl secrets set SECRET_KEY_BASE="<nova-chave>"
```

## Próximos passos

Após o deploy inicial:
1. Configure domínio customizado no Fly.io dashboard
2. Se usar banco de dados, considere usar PostgreSQL do Fly.io ou Supabase
3. Monitore a app em [https://fly.io/dashboard](https://fly.io/dashboard)
