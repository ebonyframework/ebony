# Ajouter une route


Les fichiers générés sont les vôtres. Pour ajouter une route, ajoutez une `OpérationHTTP` au contrôleur de la ressource (`app/http/produit/ControleurProduit.owl`), sur le modèle des routes générées. Celle-ci renvoie le nombre de produits ; elle est protégée par jeton comme les autres.

```owl
CompteProduit est une OpérationHTTP
	PROPRIETES
		Méthode  = httpGet
		Chemin   = ["compte-produits"]
		Réponses = [httpOK, httpServiceIndisponible, httpErreurServeur]
		CodeÉtat = httpOK
	FIN
	PROCEDURE surRequête() : chaîne
		oRepository est un cRepoProduitSql(cEbServiceBase.Base())
		oService    est un cServiceProduit(oRepository)
		sCode       est une chaîne                                                     = ""
		QUAND EXCEPTION DANS
			tabProduits est un tableau de cProduit = oService.Enumere()
			j           est un JSON
			j["compte"] = tabProduits..Occurrence
			MoiMême..Réponse..TypeContenu = "application/json"
			MoiMême..Réponse..Corps       = JSONVersChaîne(j, psdMinifie)
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

`GET /api/compte-produits` répond `{"compte":2}` avec un jeton, 401 sans. La route passe par le **service**, jamais par le repository, et traduit toute exception en réponse JSON : voir [le chemin d'une requête](architecture.md) et [les erreurs](erreurs.md).

## Un segment variable dans l'adresse

Un nom sans guillemets dans `Chemin` est un **segment variable** : OWL le lie au paramètre de `surRequête` du même nom, converti vers le type déclaré. Il peut être suivi de segments fixes ou d'autres segments variables :

```owl
Chemin = ["categories", cle, "produits"]          // GET /api/categories/7/produits
Chemin = ["sections", code, "articles", num]      // GET /api/sections/a/articles/3
PROCEDURE surRequête(code est une chaîne, num est un entier) : chaîne
```

Vérifié avec OWL 1.8.1 sous `owl serve` : `/api/categories/7/produits` répond 200 et `cle` vaut 7, `/api/categories/7` et `/api/categories/7/autre` répondent 404.

**Un entier illisible vaut 0, il ne provoque pas d'erreur** : `/api/categories/abc/produits` répond 200 avec `cle` à 0. Une route qui reçoit un entier doit donc traiter 0 comme « introuvable » (c'est ce que font les routes générées : 404).

