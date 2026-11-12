#!/bin/sh
# Test d'integration de l'installateur Linux (install/install.sh), contre une archive deja construite.
#   sh tests/integration/installateur.sh <dossier>      <dossier> contient ebony.tar.gz et ebony.tar.gz.sha256 (voir scripts/construit-archive.ps1 -NomsFixes)
# Variables facultatives : EBONY_WSL_OWL_BIN = dossier de owl a ajouter au PATH (quand owl n'y est pas) ; EBONY_INSTALLATEUR = chemin de install.sh (defaut : ../../install/install.sh).
# Tout se passe dans des dossiers temporaires ; ni ~/.local ni le PATH de l'utilisateur ne sont touches. Code 0 si tout passe, 1 sinon.
# Ce fichier reste ASCII.

set -u

ARCHIVES=${1:-}
[ -n "$ARCHIVES" ] && [ -f "$ARCHIVES/ebony.tar.gz" ] && [ -f "$ARCHIVES/ebony.tar.gz.sha256" ] || { echo "usage : sh installateur.sh <dossier avec ebony.tar.gz et ebony.tar.gz.sha256>" >&2; exit 2; }
ICI=$(cd "$(dirname "$0")" && pwd)
INSTALLATEUR=${EBONY_INSTALLATEUR:-$ICI/../../install/install.sh}
[ -f "$INSTALLATEUR" ] || { echo "install.sh introuvable : $INSTALLATEUR" >&2; exit 2; }
if [ -n "${EBONY_WSL_OWL_BIN:-}" ]; then PATH=$EBONY_WSL_OWL_BIN:$PATH; export PATH; fi
command -v owl >/dev/null 2>&1 || { echo "IGNORE : owl n'est pas dans le PATH (donnez EBONY_WSL_OWL_BIN) : l'installateur le refuserait."; exit 0; }

ECHECS=0
verifie() {
    # $1 titre ; $2 : 0 si vrai
    if [ "$2" -eq 0 ]; then echo "  [OK]     $1"; else echo "  [ECHEC]  $1"; [ -n "${3:-}" ] && echo "           $3"; ECHECS=$((ECHECS + 1)); fi
}
contient() { case $1 in *"$2"*) return 0 ;; *) return 1 ;; esac; }

ESPACE=$(mktemp -d "${TMPDIR:-/tmp}/ebony-test-installateur.XXXXXX") || exit 2
trap 'rm -rf "$ESPACE"' EXIT
# TMPDIR propre au test : on y verifie qu'aucun dossier temporaire de l'installateur ne reste.
TEMP_TEST=$ESPACE/tmp; mkdir "$TEMP_TEST"

lance() {
    # $1 : EBONY_URL_BASE ; $2 : numero du dossier d'installation. Ecrit la sortie dans $SORTIE et le code dans $CODE.
    SORTIE=$(TMPDIR=$TEMP_TEST EBONY_URL_BASE=$1 EBONY_HOME=$ESPACE/share$2 EBONY_BIN=$ESPACE/bin$2 sh "$INSTALLATEUR" 2>&1 </dev/null)
    CODE=$?
}
VERSION=$(tar -xzOf "$ARCHIVES/ebony.tar.gz" --wildcards '*/modules/core/execution/VERSION' 2>/dev/null | head -n 1 | tr -d '\r\n ')
verifie "la version se lit dans l'archive ($VERSION)" "$([ -n "$VERSION" ] && echo 0 || echo 1)"

echo "installation normale (archive locale)"
lance "$ARCHIVES" 1
verifie "code 0" "$CODE" "$SORTIE"
verifie "somme verifiee, ebony installe" "$(contient "$SORTIE" 'somme SHA-256 verifiee' && contient "$SORTIE" "ebony $VERSION est installe" && echo 0 || echo 1)" "$SORTIE"
verifie "le dossier de la version existe, avec INSTALLE" "$([ -f "$ESPACE/share1/$VERSION/INSTALLE" ] && echo 0 || echo 1)"
verifie "bin/ebony est executable" "$([ -x "$ESPACE/share1/$VERSION/bin/ebony" ] && echo 0 || echo 1)"
verifie "les points d'entree reduits sont la (.commandes/doctor)" "$([ -f "$ESPACE/share1/$VERSION/.commandes/doctor/ebony.owl" ] && echo 0 || echo 1)"
verifie "le lien ebony pointe sur le lanceur de la version" "$([ "$(readlink "$ESPACE/bin1/ebony")" = "$ESPACE/share1/$VERSION/bin/ebony" ] && echo 0 || echo 1)" "$(readlink "$ESPACE/bin1/ebony")"
verifie "il dit d'ajouter le dossier du lien au PATH (il n'y est pas)" "$(contient "$SORTIE" 'export PATH=' && echo 0 || echo 1)" "$SORTIE"
verifie "aucun dossier temporaire ne reste" "$([ -z "$(ls -A "$TEMP_TEST")" ] && echo 0 || echo 1)" "$(ls -A "$TEMP_TEST")"
VUE=$(PATH=$ESPACE/bin1:$PATH ebony --version 2>&1)
verifie "ebony --version par le lien" "$([ "$VUE" = "ebony $VERSION" ] && echo 0 || echo 1)" "$VUE"
mkdir "$ESPACE/travail"
DOCTOR=$(cd "$ESPACE/travail" && PATH=$ESPACE/bin1:$PATH ebony doctor 2>&1)
verifie "ebony doctor par le lien : aucune erreur" "$(contient "$DOCTOR" '0 erreur(s)' && echo 0 || echo 1)" "$DOCTOR"
NEW=$(cd "$ESPACE/travail" && PATH=$ESPACE/bin1:$PATH ebony new boutique 2>&1)
verifie "ebony new boutique par le lien : projet cree" "$([ -f "$ESPACE/travail/boutique/ebony.conf" ] && echo 0 || echo 1)" "$NEW"

echo "reinstallation : rien n'est recopie"
AVANT=$(cd "$ESPACE/share1" && find . -type f | sort | wc -l)
lance "$ARCHIVES" 1
verifie "code 0 et « deja installee »" "$([ "$CODE" -eq 0 ] && contient "$SORTIE" 'deja installee' && echo 0 || echo 1)" "$SORTIE"
verifie "le nombre de fichiers n'a pas change" "$([ "$(cd "$ESPACE/share1" && find . -type f | sort | wc -l)" = "$AVANT" ] && echo 0 || echo 1)"

echo "somme fausse : refus, rien d'installe, rien ne reste"
mkdir "$ESPACE/fausse"; cp "$ARCHIVES/ebony.tar.gz" "$ESPACE/fausse/"
echo "0000000000000000000000000000000000000000000000000000000000000000  ebony.tar.gz" > "$ESPACE/fausse/ebony.tar.gz.sha256"
lance "$ESPACE/fausse" 2
verifie "code 1 et la somme est refusee" "$([ "$CODE" -eq 1 ] && contient "$SORTIE" 'ne correspond pas' && echo 0 || echo 1)" "$SORTIE"
verifie "rien n'est installe" "$([ ! -e "$ESPACE/share2" ] && [ ! -e "$ESPACE/bin2" ] && echo 0 || echo 1)"
verifie "aucun dossier temporaire ne reste" "$([ -z "$(ls -A "$TEMP_TEST")" ] && echo 0 || echo 1)"

echo "archive tronquee (somme du fichier tronque) : refus, rien d'installe"
mkdir "$ESPACE/tronquee"; head -c 20000 "$ARCHIVES/ebony.tar.gz" > "$ESPACE/tronquee/ebony.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then SOMME_TRONQUEE=$(sha256sum "$ESPACE/tronquee/ebony.tar.gz" | awk '{print $1}'); else SOMME_TRONQUEE=$(shasum -a 256 "$ESPACE/tronquee/ebony.tar.gz" | awk '{print $1}'); fi
echo "$SOMME_TRONQUEE  ebony.tar.gz" > "$ESPACE/tronquee/ebony.tar.gz.sha256"
lance "$ESPACE/tronquee" 3
verifie "code 1" "$([ "$CODE" -eq 1 ] && echo 0 || echo 1)" "$SORTIE"
verifie "rien n'est installe" "$([ ! -e "$ESPACE/share3" ] && echo 0 || echo 1)"

echo "fichier de somme absent ou illisible"
mkdir "$ESPACE/sansomme"; cp "$ARCHIVES/ebony.tar.gz" "$ESPACE/sansomme/"
lance "$ESPACE/sansomme" 4
verifie "code 1 : fichier introuvable" "$([ "$CODE" -eq 1 ] && contient "$SORTIE" 'introuvable' && echo 0 || echo 1)" "$SORTIE"
echo "pas une somme" > "$ESPACE/sansomme/ebony.tar.gz.sha256"
lance "$ESPACE/sansomme" 4
verifie "code 1 : forme de somme refusee" "$([ "$CODE" -eq 1 ] && contient "$SORTIE" "pas la forme attendue" && echo 0 || echo 1)" "$SORTIE"

echo "un lien ebony existant ailleurs n'est pas remplace"
mkdir -p "$ESPACE/bin5"; ln -s /bin/true "$ESPACE/bin5/ebony"
lance "$ARCHIVES" 5
verifie "code 0, avertissement, lien inchange" "$([ "$CODE" -eq 0 ] && contient "$SORTIE" 'pointe ailleurs' && [ "$(readlink "$ESPACE/bin5/ebony")" = /bin/true ] && echo 0 || echo 1)" "$SORTIE"
verifie "il ne dit pas « est installe » quand la commande n'est pas liee" "$(contient "$SORTIE" 'PAS liee' && echo 0 || echo 1)" "$SORTIE"

echo "une version installee par autre chose que ce script n'est pas ecrasee"
mkdir -p "$ESPACE/share6/$VERSION"; echo "autre" > "$ESPACE/share6/$VERSION/a-moi.txt"
lance "$ARCHIVES" 6
verifie "code 1, le dossier est laisse" "$([ "$CODE" -eq 1 ] && [ -f "$ESPACE/share6/$VERSION/a-moi.txt" ] && [ ! -f "$ESPACE/share6/$VERSION/INSTALLE" ] && echo 0 || echo 1)" "$SORTIE"

echo "sans owl dans le PATH : refus net"
SORTIE=$(PATH=/usr/bin:/bin TMPDIR=$TEMP_TEST EBONY_URL_BASE=$ARCHIVES EBONY_HOME=$ESPACE/share7 EBONY_BIN=$ESPACE/bin7 sh "$INSTALLATEUR" 2>&1 </dev/null); CODE=$?
if PATH=/usr/bin:/bin command -v owl >/dev/null 2>&1; then
    echo "  [IGNORE] owl est dans /usr/bin ou /bin : le cas « sans owl » ne peut pas etre rejoue ici"
else
    verifie "code 1 et le message nomme owl" "$([ "$CODE" -eq 1 ] && contient "$SORTIE" 'owl' && contient "$SORTIE" 'Rien n'"'"'a ete installe' && echo 0 || echo 1)" "$SORTIE"
    verifie "rien n'est installe" "$([ ! -e "$ESPACE/share7" ] && echo 0 || echo 1)"
fi

echo "lance par un tube, comme « curl ... | sh »"
SORTIE=$(cat "$INSTALLATEUR" | TMPDIR=$TEMP_TEST EBONY_URL_BASE=$ARCHIVES EBONY_HOME=$ESPACE/share8 EBONY_BIN=$ESPACE/bin8 sh 2>&1); CODE=$?
verifie "code 0 par le tube" "$CODE" "$SORTIE"
verifie "ebony installe" "$([ -f "$ESPACE/share8/$VERSION/INSTALLE" ] && echo 0 || echo 1)"

echo "telechargement HTTP reel, avec une redirection comme celle de GitHub"
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    mkdir -p "$ESPACE/serveur/fichiers"; cp "$ARCHIVES/ebony.tar.gz" "$ARCHIVES/ebony.tar.gz.sha256" "$ESPACE/serveur/fichiers/"
    cat > "$ESPACE/serveur/serveur.py" <<'PYEOF'
import http.server, socketserver, sys, os
os.chdir(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/release/'):
            self.send_response(302); self.send_header('Location', '/fichiers/' + self.path[len('/release/'):]); self.end_headers(); return
        return super().do_GET()
    def log_message(self, *a): pass
with socketserver.TCPServer(('127.0.0.1', 0), H) as s:
    open(sys.argv[1], 'w').write(str(s.server_address[1]))
    s.serve_forever()
PYEOF
    python3 "$ESPACE/serveur/serveur.py" "$ESPACE/serveur/port" "$ESPACE/serveur" &
    PID_SERVEUR=$!
    ATTENTE=0; while [ ! -s "$ESPACE/serveur/port" ] && [ $ATTENTE -lt 50 ]; do sleep 0.1; ATTENTE=$((ATTENTE + 1)); done
    PORT=$(cat "$ESPACE/serveur/port" 2>/dev/null || true)
    if [ -n "$PORT" ]; then
        lance "http://127.0.0.1:$PORT/release" 9
        verifie "code 0 : telechargement suivi a travers la redirection" "$CODE" "$SORTIE"
        verifie "ebony installe depuis HTTP" "$([ -f "$ESPACE/share9/$VERSION/INSTALLE" ] && echo 0 || echo 1)"
        lance "http://127.0.0.1:$PORT/inconnu" 10
        verifie "adresse inconnue : code 1, rien d'installe" "$([ "$CODE" -eq 1 ] && contient "$SORTIE" 'telechargement impossible' && [ ! -e "$ESPACE/share10" ] && echo 0 || echo 1)" "$SORTIE"
    else
        verifie "le serveur HTTP de test a demarre" 1 ""
    fi
    kill "$PID_SERVEUR" 2>/dev/null; wait "$PID_SERVEUR" 2>/dev/null
else
    echo "  [IGNORE] python3 ou curl absent : le telechargement HTTP n'est pas rejoue"
fi
verifie "aucun dossier temporaire ne reste, a la fin" "$([ -z "$(ls -A "$TEMP_TEST")" ] && echo 0 || echo 1)" "$(ls -A "$TEMP_TEST")"

echo ""
if [ "$ECHECS" -eq 0 ]; then echo "INSTALLATEUR LINUX : TOUT PASSE"; exit 0; fi
echo "INSTALLATEUR LINUX : $ECHECS ECHEC(S)"
exit 1
