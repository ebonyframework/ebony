#!/bin/sh
# Installateur d'ebony pour Linux. En une ligne :
#
#   curl -fsSL https://github.com/ebonyframework/ebony/releases/latest/download/install.sh | sh
#
# Ce que fait ce script, dans l'ordre :
#   1. verifie que "owl" est dans le PATH (ebony est ecrit en OWL). Il N'INSTALLE PAS OWL ;
#   2. telecharge ebony.tar.gz et ebony.tar.gz.sha256 (la derniere release) dans UN dossier temporaire qu'il cree, et verifie la somme SHA-256 ;
#   3. copie ebony dans ~/.local/share/ebony/<version>/ (un dossier par version, jamais ecrase) et fait un lien ~/.local/bin/ebony vers son lanceur ;
#   4. supprime le dossier temporaire (le seul dossier que ce script supprime).
# Aucun droit root n'est utile, et ce script ne modifie ni votre PATH ni vos fichiers de profil : il vous dit la ligne a ajouter si ~/.local/bin n'est pas dans le PATH.
# La somme SHA-256 protege d'un telechargement corrompu, pas d'une release compromise : lisez ce script avant de l'executer si vous voulez.
#
# Variables d'environnement facultatives (essais et miroirs) :
#   EBONY_URL_BASE   adresse (https://...) ou DOSSIER local qui contient ebony.tar.gz et ebony.tar.gz.sha256 (defaut : la derniere release de ebonyframework/ebony)
#   EBONY_HOME       dossier des versions (defaut : ${XDG_DATA_HOME:-~/.local/share}/ebony)
#   EBONY_BIN        dossier du lien « ebony » (defaut : ~/.local/bin)
# Pour retirer ebony : rm -rf ~/.local/share/ebony ; rm ~/.local/bin/ebony
# Ce fichier reste ASCII.

set -eu

VERSION_OWL_REFERENCE=1.8.1
ADRESSE_PAR_DEFAUT=https://github.com/ebonyframework/ebony/releases/latest/download
BASE=${EBONY_URL_BASE:-$ADRESSE_PAR_DEFAUT}
DOSSIER_VERSIONS=${EBONY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ebony}
DOSSIER_LIEN=${EBONY_BIN:-$HOME/.local/bin}

dis() { echo "ebony : $*"; }
avertit() { echo "ebony : ATTENTION : $*" >&2; }
echoue() { echo "ebony : ECHEC : $*" >&2; exit 1; }

# 1. Les outils dont ce script a besoin, puis OWL.
for OUTIL in tar mktemp awk head tr cp mv ln chmod; do
    command -v "$OUTIL" >/dev/null 2>&1 || echoue "la commande « $OUTIL » est introuvable. Rien n'a ete installe."
done
case $BASE in
    http://*|https://*)
        if command -v curl >/dev/null 2>&1; then TELECHARGE=curl
        elif command -v wget >/dev/null 2>&1; then TELECHARGE=wget
        else echoue "ni curl ni wget n'est installe : il en faut un pour telecharger. Rien n'a ete installe."
        fi
        ;;
    *) TELECHARGE=copie ;;
esac
if command -v sha256sum >/dev/null 2>&1; then SOMME="sha256sum"
elif command -v shasum >/dev/null 2>&1; then SOMME="shasum -a 256"
else echoue "ni sha256sum ni shasum n'est installe : la somme SHA-256 ne peut pas etre verifiee. Rien n'a ete installe."
fi

command -v owl >/dev/null 2>&1 || echoue "la commande « owl » est introuvable dans le PATH. Installez d'abord OWL (https://github.com/followthewhiteowl/neowl), puis relancez. Rien n'a ete installe."
VERSION_OWL=$(owl --version 2>/dev/null </dev/null | head -n 1 | awk '{print $2}')
case $VERSION_OWL in
    "$VERSION_OWL_REFERENCE") ;;
    "") avertit "la version d'OWL n'a pas pu etre lue (owl --version)." ;;
    *) avertit "OWL $VERSION_OWL est installe ; ebony est verifie avec OWL $VERSION_OWL_REFERENCE. L'installation continue." ;;
esac

# 2. Le dossier temporaire : cree ici, supprime a la fin (le nom vient de mktemp, jamais d'un texte tape).
TRAVAIL=$(mktemp -d "${TMPDIR:-/tmp}/ebony-install.XXXXXX") || echoue "impossible de creer un dossier temporaire."
[ -n "$TRAVAIL" ] && [ -d "$TRAVAIL" ] || echoue "impossible de creer un dossier temporaire."
nettoie() { case $TRAVAIL in */ebony-install.*) rm -rf "$TRAVAIL" ;; esac; }
trap nettoie EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

recupere() {
    # $1 : nom du fichier de la release ; $2 : ou l'ecrire
    case $TELECHARGE in
        curl) curl -fsSL "${BASE%/}/$1" -o "$2" || echoue "telechargement impossible : ${BASE%/}/$1" ;;
        wget) wget -q -O "$2" "${BASE%/}/$1" || echoue "telechargement impossible : ${BASE%/}/$1" ;;
        *) [ -f "$BASE/$1" ] || echoue "fichier introuvable : $BASE/$1"; cp "$BASE/$1" "$2" ;;
    esac
}

dis "recuperation de ebony.tar.gz depuis ${BASE%/}"
recupere ebony.tar.gz "$TRAVAIL/ebony.tar.gz"
recupere ebony.tar.gz.sha256 "$TRAVAIL/ebony.tar.gz.sha256"

# 3. La somme SHA-256 (premier mot du fichier .sha256, 64 caracteres hexadecimaux).
SOMME_ATTENDUE=$(head -n 1 "$TRAVAIL/ebony.tar.gz.sha256" | awk '{print $1}' | tr 'A-F' 'a-f')
case $SOMME_ATTENDUE in
    *[!0-9a-f]*|"") echoue "le fichier ebony.tar.gz.sha256 n'a pas la forme attendue (une somme SHA-256). Rien n'a ete installe." ;;
esac
[ ${#SOMME_ATTENDUE} -eq 64 ] || echoue "le fichier ebony.tar.gz.sha256 n'a pas la forme attendue (64 caracteres). Rien n'a ete installe."
SOMME_REELLE=$($SOMME "$TRAVAIL/ebony.tar.gz" | awk '{print $1}' | tr 'A-F' 'a-f')
[ "$SOMME_REELLE" = "$SOMME_ATTENDUE" ] || echoue "la somme SHA-256 de ebony.tar.gz ne correspond pas (attendue $SOMME_ATTENDUE, obtenue $SOMME_REELLE). Rien n'a ete installe."
dis "somme SHA-256 verifiee."

# 4. L'extraction : un seul dossier ebony-<version>, avec sa VERSION.
mkdir "$TRAVAIL/archive"
tar -xzf "$TRAVAIL/ebony.tar.gz" -C "$TRAVAIL/archive" || echoue "l'archive ne s'extrait pas. Rien n'a ete installe."
NB_DOSSIERS=0
RACINE_EBONY=
for D in "$TRAVAIL"/archive/ebony-*; do
    [ -d "$D" ] || continue
    NB_DOSSIERS=$((NB_DOSSIERS + 1))
    RACINE_EBONY=$D
done
[ "$NB_DOSSIERS" -eq 1 ] || echoue "l'archive ne contient pas un seul dossier ebony-<version> (trouve : $NB_DOSSIERS). Rien n'a ete installe."
[ -f "$RACINE_EBONY/modules/core/execution/VERSION" ] && [ -f "$RACINE_EBONY/bin/ebony" ] || echoue "l'archive est incomplete (bin/ebony ou VERSION absent). Rien n'a ete installe."
VERSION=$(head -n 1 "$RACINE_EBONY/modules/core/execution/VERSION" | tr -d '\r\n ')
case $VERSION in
    *[!0-9.]*|""|.*|*.) echoue "la version lue dans l'archive (« $VERSION ») n'a pas la forme majeur.mineur.correctif. Rien n'a ete installe." ;;
esac

# 5. La copie : un dossier par version, copie dans un dossier voisin puis renommee (jamais a moitie ecrite) ; une version deja installee n'est pas recopiee.
CIBLE=$DOSSIER_VERSIONS/$VERSION
if [ -e "$CIBLE" ]; then
    [ -f "$CIBLE/INSTALLE" ] || echoue "$CIBLE existe deja et n'a pas ete installe par ce script : il n'est pas touche. Rien n'a ete installe."
    dis "la version $VERSION est deja installee dans $CIBLE : rien n'est recopie."
else
    mkdir -p "$DOSSIER_VERSIONS" || echoue "impossible de creer $DOSSIER_VERSIONS."
    PROVISOIRE=$DOSSIER_VERSIONS/.installation-$$
    rm -rf "$PROVISOIRE"
    mkdir "$PROVISOIRE" || echoue "impossible de creer $PROVISOIRE."
    cp -R "$RACINE_EBONY/." "$PROVISOIRE/" || { rm -rf "$PROVISOIRE"; echoue "la copie dans $DOSSIER_VERSIONS a echoue."; }
    chmod +x "$PROVISOIRE/bin/ebony"
    printf '%s\n' "$VERSION" > "$PROVISOIRE/INSTALLE"
    mv "$PROVISOIRE" "$CIBLE" || { rm -rf "$PROVISOIRE"; echoue "impossible de placer la version dans $CIBLE."; }
    dis "ebony $VERSION copie dans $CIBLE"
fi

# 6. Le lien ~/.local/bin/ebony : remplace seulement un lien qui pointe deja dans notre dossier de versions ; tout autre fichier ou lien est laisse, et dit.
LIEN=$DOSSIER_LIEN/ebony
mkdir -p "$DOSSIER_LIEN" || echoue "impossible de creer $DOSSIER_LIEN."
LIEN_POSE=oui
if [ -L "$LIEN" ]; then
    CIBLE_LIEN=$(readlink "$LIEN" 2>/dev/null || true)
    case $CIBLE_LIEN in
        "$DOSSIER_VERSIONS"/*) ln -sfn "$CIBLE/bin/ebony" "$LIEN" ;;
        *) LIEN_POSE=non; avertit "$LIEN existe deja et pointe ailleurs ($CIBLE_LIEN) : il n'est pas modifie. Pour utiliser cette version : ln -sfn $CIBLE/bin/ebony $LIEN" ;;
    esac
elif [ -e "$LIEN" ]; then
    LIEN_POSE=non
    avertit "$LIEN existe deja (ce n'est pas un lien) : il n'est pas modifie. Pour utiliser cette version, appelez $CIBLE/bin/ebony."
else
    ln -s "$CIBLE/bin/ebony" "$LIEN" || echoue "impossible de creer le lien $LIEN."
fi

# 7. Controle : le lanceur repond (« ebony --version » ne lance pas owl).
VERSION_INSTALLEE=$("$CIBLE/bin/ebony" --version 2>&1 </dev/null) || echoue "le lanceur installe ne repond pas : $VERSION_INSTALLEE"
echo ""
if [ "$LIEN_POSE" = "oui" ]; then dis "$VERSION_INSTALLEE est installe."; else dis "$VERSION_INSTALLEE est copie dans $CIBLE, mais la commande ebony n'est PAS liee (voir l'avertissement ci-dessus)."; fi
if [ "$LIEN_POSE" = "oui" ]; then
    case ":$PATH:" in
        *":$DOSSIER_LIEN:"*) dis "lancez : ebony doctor" ;;
        *)
            dis "$DOSSIER_LIEN n'est pas dans votre PATH. Ajoutez cette ligne a ~/.profile (ou au fichier de votre shell), puis ouvrez un nouveau terminal :"
            echo "    export PATH=\"$DOSSIER_LIEN:\$PATH\""
            dis "ensuite : ebony doctor"
            ;;
    esac
fi
