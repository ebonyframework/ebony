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

