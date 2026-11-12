# Tutoriel : construire une petite boutique

Les [premiers pas](premiers-pas.md) génèrent une ressource. Ce tutoriel va plus loin : **deux tables liées**, une **validation** dans le contrôleur, une **règle métier** dans le service, une **route de votre cru**, et un **test** de la règle. À la fin, vous savez où écrire quoi dans un projet Ebony ; la carte des couches est dans [le chemin d'une requête](architecture.md). Chaque commande et chaque code de ce guide a été rejoué (Windows, OWL 1.8.1, SQLite) ; les réponses citées sont celles du service.

Prérequis : Ebony installé ([installation](installation.md)), `ebony doctor` sans erreur. Chaque commande, chaque modification de code et chaque réponse citées ont été rejouées telles quelles sur la version 0.1.0 publiée (Windows, OWL 1.8.1, SQLite).

## 1. Deux ressources liées

Une catégorie a plusieurs produits ; un produit référence sa catégorie.

```powershell
ebony new boutique ; cd boutique
Copy-Item .env.exemple .env ; Copy-Item .env.secrets.exemple .env.secrets

ebony make migration CreeCategories --champs 'id:entier*,nom:texte' --table categories
ebony make migration CreeProduits   --champs 'id:entier*,nom:texte,prix:reel,categorie:entier@categories.id' --table produits
ebony make resource Categorie --champs 'id:entier*,nom:texte' --table categories
ebony make resource Produit   --champs 'id:entier*,nom:texte,prix:reel,categorie:entier@categories.id' --table produits

ebony migrate
ebony token create tuto            # copiez le secret (eb_…)
```

`categorie:entier@categories.id` déclare une clé étrangère : la migration écrit `"categorie" INTEGER NOT NULL REFERENCES "categories" ("id")`. Les deux migrations sont écrites dans la même minute : elles passent dans l'**ordre alphabétique** de leur intention, `CreeCategories` avant `CreeProduits`, ce qu'il faut ici.

Lancez le service (`owl serve --port 8080`), puis, dans un second terminal, avec le secret à la place de `eb_…` :

```powershell
curl.exe -s -X POST -H "Authorization: Bearer eb_…" -H "Content-Type: application/json" --data-binary "@categorie.json" http://127.0.0.1:8080/api/categories
# {"id":1,"nom":"Papeterie"}
```

(`categorie.json` contient `{"nom":"Papeterie"}` : écrivez le corps dans un fichier, voir les [premiers pas](premiers-pas.md).) Un produit se crée de la même façon avec `{"nom":"Cahier","prix":2.5,"categorie":1}` sur `/api/produits`.

## 2. La validation : dans le contrôleur

Le contrôleur vérifie **ce que le client envoie**. Le fichier généré refuse déjà un nom vide ; ajoutons : un prix ne peut pas être négatif. Dans `app/http/produit/ControleurProduit.owl`, dans les **deux** routes `CreeProduit` et `ModifieProduit`, à la suite du contrôle du nom :

```owl
SI SansEspace(stCorps.Nom) = "" ALORS
	ExceptionDéclenche(400, "Le champ « nom » est obligatoire.")
FIN
SI stCorps.Prix < 0 ALORS
	ExceptionDéclenche(400, "Le champ « prix » ne peut pas être négatif.")
FIN
```

Relancez le service. Un prix négatif donne :

```text
POST /api/produits  {"nom":"Gomme","prix":-1,"categorie":1}
  → 400  {"code":"invalide","message":"Le champ « prix » ne peut pas être négatif."}
```

L'exception levée avec le code 400 est attrapée par la route (`QUAND EXCEPTION`), traduite en statut HTTP et en JSON : voir [les erreurs](erreurs.md).

## 3. La règle métier : dans le service

Une règle métier ne dépend ni du HTTP ni de la base. Règle : **deux produits d'une même catégorie ne portent pas le même nom** (casse ignorée). Dans `app/services/produit/cServiceProduit.owl`, remplacez la méthode `Ajoute` :

```owl
// Règle métier : deux produits d'une même catégorie ne portent pas le même nom (casse ignorée).
PROCEDURE PUBLIQUE Ajoute(entite est un cProduit) : cProduit
	POUR TOUT oExistant DE :oRepository.Enumere()
		SI oExistant.LitCategorie() = entite.LitCategorie() ET Minuscule(oExistant.LitNom()) = Minuscule(entite.LitNom()) ALORS
			ExceptionDéclenche(409, "Ce produit existe déjà dans cette catégorie")
		FIN
	FIN
	RENVOYER :oRepository.Ajoute(entite)
FIN
```

Le service ne sait pas d'où vient l'appel : il lève une exception, la route la traduit. Avec « Cahier » déjà présent dans la catégorie 1 :

```text
POST /api/produits  {"nom":"cahier","prix":3,"categorie":1}
  → 409  {"code":"conflit","message":"Ce produit existe déjà dans cette catégorie"}
POST /api/produits  {"nom":"Cahier","prix":2,"categorie":2}     (autre catégorie)
  → 201  {"id":3,"nom":"Cahier","prix":2,"categorie":2}
```

## 4. Une route de votre cru

Les produits d'une catégorie : `GET /api/categories/{cle}/produits`. Ajoutez, à la fin de `ControleurProduit.owl` (avant le dernier `FIN`), une `OpérationHTTP` sur le modèle de `ListeProduit` :

```owl
// Une route à vous : les produits d'une catégorie (GET /api/categories/{cle}/produits).
ProduitsDeCategorie est une OpérationHTTP
	PROPRIETES
		Méthode  = httpGet
		Chemin   = ["categories", cle, "produits"]
		Réponses = [httpOK, httpServiceIndisponible, httpErreurServeur]
		CodeÉtat = httpOK
	FIN
	PROCEDURE surRequête(cle est un entier) : chaîne
		oRepository est un cRepoProduitSql(cEbServiceBase.Base())
		oService    est un cServiceProduit(oRepository)
		sCode       est une chaîne                                                     = ""
		QUAND EXCEPTION DANS
			sJson est une chaîne = ""
			POUR TOUT oEntite DE oService.Enumere()
				SI oEntite.LitCategorie() = cle ALORS
					SI sJson <> "" ALORS
						sJson += ","
					FIN
					sJson += oEntite.EnJson()
				FIN
			FIN
			MoiMême..Réponse..TypeContenu = "application/json"
			MoiMême..Réponse..Corps       = "[" + sJson + "]"
		FAIRE
			sCode = ExceptionInfo(errCode)
			EbJournaliseErreurHttp(sCode, ExceptionInfo(errMessage))
			MoiMême..Réponse..CodeÉtat    = EbStatutHttpDeCode(sCode)
			MoiMême..Réponse..TypeContenu = "application/json"
			MoiMême..Réponse..Corps       = EbCorpsErreurHttp(sCode, ExceptionInfo(errMessage))
		FIN
		RENVOYER ""
	FIN
FIN
```

Le paramètre `cle` de la route est lu depuis l'adresse (`/api/categories/1/produits`) ; la route est **protégée par jeton** comme les autres, sans rien écrire. Elle passe par le **service**, jamais par le repository.

```text
GET /api/categories/1/produits  →  200  [{"id":1,"nom":"Cahier","prix":2.5,"categorie":1},{"id":2,"nom":"Stylo","prix":1,"categorie":1}]
GET /api/categories/2/produits  →  200  [{"id":3,"nom":"Cahier","prix":2,"categorie":2}]
```

## 5. Tester la règle, sans base

Les tests générés utilisent le repository **en mémoire** : ils s'exécutent sans base ni fichier. Ajoutez, à la fin de `tests/unitaires/produit/test_cServiceProduit.owl`, un scénario par règle :

```owl
// Deux produits de la même catégorie ne portent pas le même nom (casse ignorée) : le service lève 409 et n'enregistre pas le doublon.
PROCEDURE scenario_service_refuse_un_doublon_dans_la_meme_categorie()
	oRepository est un cRepoProduitMemoire
	oService    est un cServiceProduit(oRepository)
	oPremier    est un cProduit(0, "Cahier", 2.5, 1)
	oService.Ajoute(oPremier)
	oDoublon est un cProduit(0, "cahier", 3, 1)
	sCode    est une chaîne = ""
	QUAND EXCEPTION DANS
		oService.Ajoute(oDoublon)
	FAIRE
		sCode = ExceptionInfo(errCode)
	FIN
	dbgVérifieEgalité(sCode, "409", "le doublon est refusé")
	dbgVérifieEgalité(oService.Enumere()..Occurrence, 1, "le doublon n'est pas enregistré")
FIN
```

```powershell
owl test -vv --filter test_cServiceProduit
# ✓ scenario scenario_service_refuse_un_doublon_dans_la_meme_categorie
# STATUS: ALL CLEAR (1 suites, 16 assertions, 6 scenarios)
```

Écrivez de la même façon un scénario « le même nom dans une autre catégorie est permis ». `owl test` recompile tout le projet à chaque suite : les 10 suites de ce projet passent en une cinquantaine de secondes (mesuré), le temps croît avec la taille du projet.

## À savoir

- **SQLite n'applique pas la clé étrangère ici.** Un produit d'une catégorie qui n'existe pas (`"categorie":99`) est accepté (201) : la contrainte déclarée dans la migration n'est pas vérifiée par la connexion (constaté ainsi). Si la catégorie doit exister, vérifiez-le vous-même dans le service (par exemple en cherchant la catégorie par son service avant d'ajouter le produit). PostgreSQL applique la contrainte (non essayé ici).
- **Un `PUT` remplace toute la ressource** : envoyez tous les champs ([détail](architecture.md#le-corps-dune-requête--une-lecture-tolérante)).
- **Chaque couche reste à sa place** : la validation de ce que le client envoie dans le contrôleur, les règles de l'application dans le service, le SQL dans le repository. Ajouter une règle ne demande jamais de toucher à la base ni au HTTP.

## Pour aller plus loin

- [Les erreurs](erreurs.md) : tous les codes, et comment répondre avec un autre statut.
- [Référence des commandes](commandes.md) : options de `make`, `migrate`, `token`.
- [Configuration et secrets](configuration.md) : passer à PostgreSQL, régler le TLS, préparer la production.
