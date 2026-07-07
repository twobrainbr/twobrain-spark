# Spark — Manual de Operação

"Inteligência" do projeto: tudo que uma nova sessão (ou você em outro PC) precisa pra operar o Spark.
**Nenhum segredo aqui** — os segredos ficam no cofre cifrado `secrets/spark-vault.tar.enc` (ver "Destravar" abaixo).

## Visão geral
- **Produto:** Spark — white-label do Chatwoot (fork em `twobrainbr/twobrain-spark`, base v4.15.1)
- **Produção:** https://spark.twobrain.com.br
- **Imagem:** `ghcr.io/twobrainbr/twobrain-spark:latest` (buildada pelo GitHub Actions)
- **Servidor:** VPS Contabo, IP `217.216.54.78`, Ubuntu 26.04 (4 vCPU / 8GB), acesso root só por chave SSH
- **Admin do Spark:** leonardo@twobrain.com.br
- **DNS:** Cloudflare (proxy ativo, modo SSL "Full") → Caddy no servidor faz o HTTPS

## Continuar de outro computador (passo a passo)
```bash
git clone https://github.com/twobrainbr/twobrain-spark.git
cd twobrain-spark
gh auth login                 # autentica no GitHub
./scripts/spark-unlock.sh     # digita a senha do cofre -> instala chave SSH + configura acesso
ssh spark-vps 'echo ok'       # testa o acesso ao servidor
```

## Arquitetura de atualização (customizar sem perder mudanças)
```
edita no fork -> git push (main) -> GitHub Actions builda imagem -> GHCR -> deploy no VPS
```
- Atualizar com nova versão do Chatwoot: `./scripts/spark-sync-upstream.sh`
- Detalhes em `SPARK.md`.

## Deploy no servidor (após um build novo)
```bash
ssh spark-vps
cd /opt/chatwoot
docker compose pull
docker compose run --rm rails bundle exec rails db:chatwoot_prepare   # migrações (idempotente)
docker compose up -d
```

## Onde as coisas vivem no servidor
- App/stack: `/opt/chatwoot` (docker-compose + `.env` com segredos)
- Proxy/HTTPS: `/etc/caddy/Caddyfile`
- Manutenção diária 00:00 BR: `/opt/maint/daily-maintenance.sh`
- Backup diário 02:00 BR: `/opt/maint/backup.sh` → `/opt/backups` (rotação 7 dias)
- Firewall Cloudflare-only: `/opt/maint/cf-firewall.sh`
- Segurança: UFW (80/443 só Cloudflare, 22 aberto), fail2ban, unattended-upgrades

## Branding / redesign (no código, compilado na imagem)
- Cores: `theme/colors.js` (paleta `woot` verde) + `app/javascript/dashboard/assets/scss/_next-colors.scss`
- Botões: `components-next/button/Button.vue` e `shared/components/Button.vue` (Green5 bg / Green11 texto, pílula, sem sombra)
- Tipografia: `_woot.scss` (Hanken Grotesk; trocar pela Borna quando houver licença webfont)
- Sombras: `tailwind.config.js` (`boxShadow` = none)
- Login: `app/javascript/v3/views/login/Index.vue`
- Logos/favicons: `public/brand-assets/`, `public/*.png`, fontes em `brand/`
- Nome/URLs: `config/installation_config.yml`

## Pendências conhecidas
- Borna: comprar licença webfont (atipo, info@atipo.es) — hoje usa Hanken Grotesk
- Google login: setar `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` no `.env`
- Meta: conectar caixas Messenger/Instagram no Spark (servidor já configurado)
- SMTP (envio de e-mail): configurar provedor no `.env`
- Backup offsite (R2/B2): configurar rclone remote `spark-offsite:`
- Imagem GHCR privada: tornar pública p/ remover o token de login do servidor
