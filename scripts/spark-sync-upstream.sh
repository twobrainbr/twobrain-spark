#!/usr/bin/env bash
# Atualiza o Spark com uma versão nova do Chatwoot, preservando as customizações.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "==> Buscando novidades do Chatwoot oficial (upstream)..."
git fetch upstream --tags --quiet

echo
echo "Tags estáveis mais recentes do Chatwoot:"
git tag -l 'v*' --sort=-v:refname | head -8
echo
read -rp "Qual tag você quer mesclar (ex: v4.16.0)? " TAG

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag '$TAG' não encontrada. Abortando."; exit 1
fi

git checkout main
echo "==> Mesclando $TAG na main..."
if git merge "$TAG" --no-edit; then
  echo
  echo "✅ Merge concluído sem conflitos."
  echo "   Revise, teste e envie:  git push origin main   (isso dispara o rebuild da imagem)"
else
  echo
  echo "⚠️  Há conflitos. Resolva os arquivos marcados e finalize:"
  echo "      git add <arquivos resolvidos>"
  echo "      git commit"
  echo "      git push origin main"
  echo
  echo "   Dica: conflitos em .github/workflows/ são esperados —"
  echo "   use 'git rm' nos arquivos que vierem do upstream."
  exit 1
fi
