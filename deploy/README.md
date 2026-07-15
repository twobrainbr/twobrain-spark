# Deploy — Spark no VPS

Infraestrutura de produção do Spark. O servidor roda a imagem personalizada
`ghcr.io/twobrainbr/twobrain-spark:latest` (buildada pelo GitHub Actions).

## Arquivos
- `docker-compose.yaml` — stack de produção (usa a imagem do GHCR)
- `.env.example` — modelo de variáveis (copiar para `/opt/chatwoot/.env` e preencher)
- `Caddyfile` — proxy reverso + HTTPS (`/etc/caddy/Caddyfile`)

## Primeiro deploy (resumo)
```bash
# no servidor, em /opt/chatwoot
docker compose pull
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up -d
```

## Atualizar produção (após um novo build da imagem)
```bash
cd /opt/chatwoot
docker compose pull                                   # baixa a imagem nova
docker compose run --rm rails bundle exec rails db:chatwoot_prepare  # migrações
docker compose up -d                                  # reinicia com a nova versão
```

## Rotinas no servidor (fora deste repo)
- `/opt/maint/daily-maintenance.sh` — limpeza diária (cron 00:00 BR)
- `/opt/maint/backup.sh` — backup diário (cron 02:00 BR) em `/opt/backups`
- `/opt/maint/cf-firewall.sh` — libera 80/443 só para IPs do Cloudflare
- Segurança: UFW, fail2ban, unattended-upgrades

> A imagem do GHCR é pública para o `pull` funcionar sem autenticação no servidor.

## Segredos e portabilidade

O código, as migrações e a definição completa da stack ficam neste repositório.
Segredos não entram na imagem nem no Git: configure `OPENAI_API_KEY` e os demais
valores no arquivo `/opt/chatwoot/.env` de cada ambiente, usando `.env.example`
como contrato de configuração. Reinicie `rails` e `sidekiq` após alterar o arquivo.
