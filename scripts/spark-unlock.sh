#!/usr/bin/env bash
# Destrava o cofre de segredos e configura ESTA máquina para operar o Spark.
# Requer: openssl, tar, git. Uso: ./scripts/spark-unlock.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

VAULT="secrets/spark-vault.tar.enc"
[ -f "$VAULT" ] || { echo "Cofre não encontrado: $VAULT"; exit 1; }

read -rsp "Senha do cofre: " PW; echo
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$VAULT" -out "$TMP/vault.tar.gz" -pass pass:"$PW" 2>/dev/null; then
  echo "❌ Senha incorreta ou cofre corrompido."; exit 1
fi
tar -xzf "$TMP/vault.tar.gz" -C "$TMP"

# 1) Instala a chave SSH do servidor
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
install -m 600 "$TMP/chatwoot_vps" "$HOME/.ssh/chatwoot_vps"
[ -f "$TMP/chatwoot_vps.pub" ] && install -m 644 "$TMP/chatwoot_vps.pub" "$HOME/.ssh/chatwoot_vps.pub"

# 2) Alias SSH (spark-vps)
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
grep -q "Host spark-vps" "$HOME/.ssh/config" || cat "$TMP/ssh_config_snippet" >> "$HOME/.ssh/config"

# 3) Credenciais para referência local (NÃO versionadas — ver .gitignore)
mkdir -p secrets
cp "$TMP/credentials.env" secrets/credentials.env.local 2>/dev/null || true
cp "$TMP/vps-opt-chatwoot.env" secrets/vps.env.local 2>/dev/null || true

echo "✅ Máquina configurada para o Spark."
echo "   Teste o acesso:  ssh spark-vps 'echo ok'"
echo "   Credenciais (local, fora do Git): secrets/credentials.env.local"
