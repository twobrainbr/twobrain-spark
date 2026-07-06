# Spark — white-label do Chatwoot (TwoBrain)

Este repositório é um **fork do [Chatwoot](https://github.com/chatwoot/chatwoot)** com as
personalizações da marca **Spark**. Ele foi montado para permitir **customizar** (cores, logo,
identidade) **e continuar recebendo as atualizações** oficiais do Chatwoot sem perder as mudanças.

- **Produção:** https://spark.twobrain.com.br
- **Base atual:** Chatwoot `v4.15.1`
- **Imagem publicada:** `ghcr.io/twobrainbr/twobrain-spark:latest`

## Como funciona

```
Este repo (main)  ──push──▶  GitHub Actions builda a imagem  ──▶  GHCR
        ▲                                                          │
        │ suas customizações (commits)                     VPS faz "pull"
        │                                                          ▼
   upstream = chatwoot/chatwoot                        spark.twobrain.com.br
```

- Cada `git push` na `main` dispara o workflow [`build-spark.yml`](.github/workflows/build-spark.yml),
  que builda a imagem e publica no GHCR.
- O servidor usa **essa** imagem (não a oficial), então tudo que você customizar aqui vai pra produção.

## Atualizar com uma nova versão do Chatwoot (sem perder customizações)

Use o helper:

```bash
./scripts/spark-sync-upstream.sh
```

Ou manualmente:

```bash
git fetch upstream --tags
git checkout main
git merge v4.16.0        # a tag nova que você quer
# resolva conflitos (só onde você customizou), depois:
git commit
git push origin main     # dispara o rebuild da imagem
```

Depois que o build terminar, atualize o servidor (ver `deploy/`).

> Conflitos em `.github/workflows/` são esperados (removemos os workflows do upstream).
> Basta `git rm` nos arquivos do upstream e seguir.

## Onde ficam as customizações da marca

| O quê | Onde | Precisa rebuild? |
|---|---|---|
| Nome, logos, favicon, cor do widget | Super Admin (`/super_admin`) — runtime | ❌ Não |
| Paleta de cores da interface | `app/javascript/dashboard/assets/scss/` + Tailwind | ✅ Sim |
| Textos/traduções | `config/locales/` e `app/javascript/dashboard/i18n/` | ✅ Sim |

## Deploy / operação do servidor

Os arquivos de infraestrutura de produção estão em [`deploy/`](deploy/) (compose, Caddyfile, exemplo de `.env`).
Rotinas de segurança, manutenção e backup vivem no VPS em `/opt/maint/`.
