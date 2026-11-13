#!/bin/bash
# Test d'intégration sous Linux : le parcours du guide « premiers pas » avec le vrai lanceur bin/ebony, un vrai owl et un vrai « owl serve ».
#
# new, doctor, make migration, make resource, migrate, token create, owl serve, curl (accueil, santé, 401 sans jeton, création et lecture avec jeton), token revoke.
# Tout se passe dans un dossier temporaire (jamais sous le dépôt : les .owl d'un projet généré y seraient chargés avec ceux d'ebony). Seul le processus « owl serve » lancé ici est arrêté (par son PID).
#
# Usage : tests/integration/linux.sh        (depuis n'importe où ; owl et curl dans le PATH)
# Code de sortie : 0 si tout passe, 1 sinon.

DEPOT=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
EBONY="$DEPOT/bin/ebony"
TRAVAIL=$(mktemp -d "${TMPDIR:-/tmp}/ebony-linux.XXXXXX")
PID_SERVICE=""
ECHECS=0

nettoie() {
    if [ -n "$PID_SERVICE" ]; then kill "$PID_SERVICE" 2>/dev/null; fi
    rm -rf "$TRAVAIL"
}
trap nettoie EXIT

verifie() { # verifie "titre" code_attendu_0_si_vrai [détail]
    if [ "$2" -eq 0 ]; then
        echo "  [OK]     $1"
    else
        echo "  [ECHEC]  $1"
        [ -n "${3:-}" ] && echo "           $3"
        ECHECS=$((ECHECS + 1))
    fi
}
contient() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

cd "$TRAVAIL" || exit 1
echo "ebony sous Linux : $(uname -sr), $(owl --version)"

echo "lanceur"
SORTIE=$("$EBONY" --version); CODE=$?
verifie "ebony --version : code 0 et « ebony X.Y.Z »" $([ $CODE -eq 0 ] && contient "$SORTIE" "ebony " && echo 0 || echo 1) "$SORTIE"
SORTIE=$("$EBONY" install 2>&1); CODE=$?
verifie "ebony install : refusé (code 2), pas de demi-installation" $([ $CODE -eq 2 ] && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" commande-inconnue 2>&1); CODE=$?
verifie "commande inconnue : code non nul" $([ $CODE -ne 0 ] && echo 0 || echo 1) "code=$CODE $SORTIE"

echo "new, doctor"
SORTIE=$("$EBONY" new boutique 2>&1); CODE=$?
verifie "new boutique : code 0, le dossier est écrit avec un chemin Linux (/…)" $([ $CODE -eq 0 ] && contient "$SORTIE" "Projet créé : $TRAVAIL/boutique" && echo 0 || echo 1) "code=$CODE $SORTIE"
verifie "aucune barre inverse dans la sortie de new" $(contient "$SORTIE" '\' && echo 1 || echo 0) "$SORTIE"
cd boutique || exit 1
cp .env.exemple .env && cp .env.secrets.exemple .env.secrets
SORTIE=$("$EBONY" doctor 2>&1); CODE=$?
verifie "doctor : code 0, 0 erreur" $([ $CODE -eq 0 ] && contient "$SORTIE" "0 erreur(s)" && echo 0 || echo 1) "code=$CODE $SORTIE"

echo "make, migrate"
CHAMPS='id:entier*,nom:texte,prix:reel,actif:booleen'
SORTIE=$("$EBONY" make migration CreeProduits --champs "$CHAMPS" 2>&1); CODE=$?
verifie "make migration : code 0" $([ $CODE -eq 0 ] && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" make resource Produit --champs "$CHAMPS" --table produits 2>&1); CODE=$?
verifie "make resource : code 0, le contrôleur est écrit (chemins avec /)" $([ $CODE -eq 0 ] && contient "$SORTIE" "app/http/produit/ControleurProduit.owl" && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" migrate 2>&1); CODE=$?
verifie "migrate : code 0, deux migrations (jetons, produits)" $([ $CODE -eq 0 ] && contient "$SORTIE" "2 migration(s)" && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" token create essai --json 2>&1); CODE=$?
JETON=$(printf '%s' "$SORTIE" | sed -n 's/.*"token":"\(eb_[^"]*\)".*/\1/p')
verifie "token create : un secret eb_" $([ $CODE -eq 0 ] && [ -n "$JETON" ] && echo 0 || echo 1) "code=$CODE $SORTIE"
IDENTIFIANT=$(printf '%s' "$SORTIE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo "owl serve"
PORT=$(( 20000 + RANDOM % 20000 ))
owl serve --port "$PORT" >"$TRAVAIL/serve.out" 2>"$TRAVAIL/serve.err" &
PID_SERVICE=$!
PRET=1
for _ in $(seq 1 90); do
    CODE_HTTP=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/health")
    if [ "$CODE_HTTP" != "000" ]; then PRET=0; break; fi
    sleep 0.7
done
verifie "le service répond (owl serve)" $PRET "$(cat "$TRAVAIL/serve.err" 2>/dev/null | head -3)"
URL="http://127.0.0.1:$PORT"
SORTIE=$(curl -s -w ' [%{http_code}]' "$URL/api")
verifie "GET /api : 200, accueil JSON" $(contient "$SORTIE" '{"statut":"ok","sante":"/api/health"} [200]' && echo 0 || echo 1) "$SORTIE"
SORTIE=$(curl -s -w ' [%{http_code}]' "$URL/api/health")
verifie "GET /api/health : 200, la base répond" $(contient "$SORTIE" '{"statut":"ok","base":"ok"} [200]' && echo 0 || echo 1) "$SORTIE"
SORTIE=$(curl -s -w ' [%{http_code}]' "$URL/api/produits")
verifie "GET /api/produits sans jeton : 401" $(contient "$SORTIE" '[401]' && echo 0 || echo 1) "$SORTIE"
SORTIE=$(curl -s -w ' [%{http_code}]' -H "Authorization: Bearer $JETON" "$URL/api/produits")
verifie "avec le jeton : 200 et liste vide" $([ "$SORTIE" = '[] [200]' ] && echo 0 || echo 1) "$SORTIE"
SORTIE=$(curl -s -w ' [%{http_code}]' -X POST -H "Authorization: Bearer $JETON" -H 'Content-Type: application/json' -d '{"nom":"Cahier","prix":2.5,"actif":true}' "$URL/api/produits")
verifie "POST : 201 et l'identifiant vient de la base" $(contient "$SORTIE" '{"id":1,"nom":"Cahier","prix":2.5,"actif":true} [201]' && echo 0 || echo 1) "$SORTIE"
SORTIE=$(curl -s -w ' [%{http_code}]' -H "Authorization: Bearer $JETON" "$URL/api/produits/1")
verifie "GET /api/produits/1 : 200" $(contient "$SORTIE" '"nom":"Cahier"' && contient "$SORTIE" '[200]' && echo 0 || echo 1) "$SORTIE"
kill "$PID_SERVICE" 2>/dev/null; wait "$PID_SERVICE" 2>/dev/null; PID_SERVICE=""

echo "token revoke"
SORTIE=$("$EBONY" token revoke "$IDENTIFIANT" 2>&1); CODE=$?
verifie "token revoke : code 0" $([ $CODE -eq 0 ] && echo 0 || echo 1) "code=$CODE $SORTIE"

echo "add : slim + add db + add auth redonne un projet api neuf"
mkdir -p "$TRAVAIL/ajout" "$TRAVAIL/reference"
cd "$TRAVAIL/ajout" || exit 1
SORTIE=$("$EBONY" new demo --kit slim 2>&1); CODE=$?
verifie "new demo --kit slim : code 0" $([ $CODE -eq 0 ] && echo 0 || echo 1) "code=$CODE $SORTIE"
cd demo || exit 1
SORTIE=$("$EBONY" add auth 2>&1); CODE=$?
verifie "add auth avant db : refusé (code 1), dit d'ajouter db d'abord" $([ $CODE -eq 1 ] && contient "$SORTIE" "ebony add db" && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" add db --json 2>&1); CODE=$?
verifie "add db : code 0, base sqlite, ebony.conf réécrit" $([ $CODE -eq 0 ] && contient "$SORTIE" '"base":"sqlite"' && contient "$SORTIE" '"ebony.conf"' && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" add db 2>&1); CODE=$?
verifie "add db une seconde fois : refusé (code 1), déjà présent" $([ $CODE -eq 1 ] && contient "$SORTIE" "dans ce projet" && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" add auth --json 2>&1); CODE=$?
verifie "add auth : code 0, la migration des jetons est écrite (chemin avec /)" $([ $CODE -eq 0 ] && contient "$SORTIE" 'database/migrations/M202611100000_CreeEbJetons.owl' && echo 0 || echo 1) "code=$CODE $SORTIE"
SORTIE=$("$EBONY" add db --base oracle 2>&1); CODE=$?
verifie "add --base oracle : usage incorrect (code 2)" $([ $CODE -eq 2 ] && echo 0 || echo 1) "code=$CODE $SORTIE"
cd "$TRAVAIL/reference" || exit 1
"$EBONY" new demo >/dev/null 2>&1
DIFFERENCES=$(diff -rq -x ebony.conf -x README.md -x AGENTS.md "$TRAVAIL/ajout/demo" "$TRAVAIL/reference/demo" 2>&1)
NB_FICHIERS=$(find "$TRAVAIL/reference/demo" -type f | wc -l)
verifie "mêmes fichiers, mêmes octets qu'un projet api neuf (hors ebony.conf, README.md, AGENTS.md)" $([ -z "$DIFFERENCES" ] && [ "$NB_FICHIERS" -ge 30 ] && echo 0 || echo 1) "$NB_FICHIERS fichiers de référence ; $DIFFERENCES"
sed 's/"kit": "slim"/"kit": "api"/' "$TRAVAIL/ajout/demo/ebony.conf" | cmp -s - "$TRAVAIL/reference/demo/ebony.conf"
verifie "ebony.conf : seul le kit noté diffère (slim contre api)" $?
cd "$TRAVAIL/ajout/demo" || exit 1
SORTIE=$("$EBONY" migrate 2>&1); CODE=$?
verifie "migrate applique la migration écrite par add auth" $([ $CODE -eq 0 ] && contient "$SORTIE" "1 migration(s)" && echo 0 || echo 1) "code=$CODE $SORTIE"
PORT=$(( 20000 + RANDOM % 20000 ))
owl serve --port "$PORT" >"$TRAVAIL/serve-ajout.out" 2>"$TRAVAIL/serve-ajout.err" &
PID_SERVICE=$!
PRET=1
for _ in $(seq 1 90); do
    CODE_HTTP=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/health")
    if [ "$CODE_HTTP" != "000" ]; then PRET=0; break; fi
    sleep 0.7
done
verifie "le service du projet obtenu par add répond (owl serve)" $PRET "$(head -3 "$TRAVAIL/serve-ajout.err" 2>/dev/null)"
SORTIE=$(curl -s -w ' [%{http_code}]' "http://127.0.0.1:$PORT/api/health")
verifie "GET /api/health : 200, la base répond" $(contient "$SORTIE" '{"statut":"ok","base":"ok"} [200]' && echo 0 || echo 1) "$SORTIE"
kill "$PID_SERVICE" 2>/dev/null; wait "$PID_SERVICE" 2>/dev/null; PID_SERVICE=""

echo
if [ "$ECHECS" -eq 0 ]; then echo "LINUX : TOUT PASSE"; exit 0; fi
echo "LINUX : $ECHECS ECHEC(S)"
exit 1
