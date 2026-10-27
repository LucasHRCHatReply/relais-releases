#!/bin/zsh
# Relais — installation ou mise à jour, sans compte GitHub et sans outil à installer :
#   curl -fsSL https://raw.githubusercontent.com/LucasHRCHatReply/relais-releases/main/installer.sh | zsh
# Le script télécharge la dernière version publiée, vérifie l'empreinte SHA-256, l'identifiant et l'équipe de signature
# (codesign --verify --deep --strict), puis lance install.sh du zip : Relais.app va dans ~/Applications, la quarantaine est
# levée sur Relais.app seulement, l'app est lancée. Une instance de Relais
# qui tourne est quittée d'abord. Historique et réglages (~/Library/Application Support/Relais) ne sont jamais touchés.
# Aucun mot de passe administrateur. Le script se lit en entier avant de le lancer.
set -uo pipefail
ZIP_URL="${RELAIS_ZIP_URL:-https://github.com/LucasHRCHatReply/relais-releases/releases/latest/download/Relais.zip}"
TEAM="JT9FY7PP7K"
BUNDLE_ID="fr.lucashi.relais"
fail() { echo "\nÉCHEC : $*" >&2; exit 1; }
step() { echo "\n[$1/3] $2"; }

step 1 "Ce Mac convient-il ?"
macos=$(sw_vers -productVersion)
(( ${macos%%.*} >= 14 )) || fail "Relais demande macOS 14 ou plus (ce Mac : $macos)."
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]] || fail "Relais ne tourne que sur les Mac à puce Apple (M1 ou plus récent)."
echo "  macOS $macos : ok"

step 2 "Téléchargement et contrôle"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/relais-install.XXXXXX") || fail "dossier temporaire impossible"
trap 'rm -rf "$WORK"' EXIT
curl -fL --silent --show-error -o "$WORK/Relais.zip" "$ZIP_URL" || fail "téléchargement impossible (réseau coupé, ou aucune version publiée) : $ZIP_URL"
if curl -fL --silent -o "$WORK/Relais.zip.sha256" "$ZIP_URL.sha256" 2>/dev/null && [[ -s "$WORK/Relais.zip.sha256" ]]; then
  want=$(awk '{print $1; exit}' "$WORK/Relais.zip.sha256"); have=$(shasum -a 256 "$WORK/Relais.zip" | awk '{print $1}')
  [[ "$want" == "$have" ]] || fail "l'empreinte SHA-256 du zip ne correspond pas à celle publiée : installation refusée."
  echo "  empreinte SHA-256 : conforme"
else
  fail "l'empreinte SHA-256 publiée est introuvable : installation refusée."
fi
ditto -x -k "$WORK/Relais.zip" "$WORK/contenu" || fail "le zip est illisible"
DIR=$(ls -d "$WORK"/contenu/Relais-* 2>/dev/null | head -1)
[[ -n "$DIR" && -d "$DIR/Relais.app" && -f "$DIR/install.sh" ]] || fail "le zip n'a pas le contenu attendu (Relais-X.Y.Z/Relais.app et install.sh)."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DIR/Relais.app/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" ]] || fail "identifiant de l'app inattendu : installation refusée."
got=$(codesign -dv "$DIR/Relais.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[[ "$got" == "$TEAM" ]] || fail "l'app n'est pas signée par l'équipe attendue ($TEAM) mais par « ${got:-aucune} » : installation refusée."
codesign --verify --deep --strict "$DIR/Relais.app" 2>/dev/null || fail "la signature de Relais.app est invalide : installation refusée."
NEW=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIR/Relais.app/Contents/Info.plist")
echo "  Relais $NEW, signature valide, équipe $TEAM : ok  ($(du -h "$WORK/Relais.zip" | cut -f1))"

step 3 "Installation"
zsh "$DIR/install.sh" "$DIR/Relais.app" || fail "l'installation a échoué (voir le message ci-dessus)."
echo "\nTerminé."
