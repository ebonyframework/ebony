# Adopter Ebony dans un projet OWL existant

Vous avez déjà un projet OWL (un `projet.owl`) et vous voulez y ajouter Ebony sans repartir de zéro. `ebony init` ajoute la bibliothèque et la configuration sans rien écraser. Il **n'écrit pas** le service REST que `ebony new` génère : c'est lui qui démarre l'application (configuration, journal, base) dont les contrôleurs générés ont besoin. Ce guide montre comment l'ajouter. Le parcours complet a été rejoué sur un projet créé par `owl new projet`, sous Windows avec OWL 1.8.1 et SQLite.

## 1. Ajouter Ebony

À la racine du projet :

```powershell
ebony init
Copy-Item .env.exemple .env
Copy-Item .env.secrets.exemple .env.secrets
```

`ebony init` accepte les mêmes options que `ebony new` (`--base sqlite|postgresql|hfsql`, `--auth [--table …]`), sans nom de projet. Il écrit : `ebony/` (la bibliothèque), `ebony.conf`, `config/env.json`, `.env.exemple` et `.env.secrets.exemple`, `.gitignore`, `README.md` et `AGENTS.md` (consignes pour un assistant de code) s'ils n'existent pas, et les migrations et fichiers des modules (la migration des jetons). **Il conserve tout fichier existant**, `projet.owl` compris, et le dit : « Conservés : projet.owl (non modifiés) ». Le projet compile ensuite sans autre changement.

## 2. Ajouter le service qui démarre l'application

Créez `app/http/ServiceMonProjet.owl` (le nom est libre, il doit être unique dans le projet) :

```owl
ServiceMonProjet est un ServiceREST
	PROPRIETES
		UrlBase = ["api"]
	FIN

	// L'application unique est posée dans cEbServiceApplication, pas dans une variable du bloc du service.
	// Une configuration invalide arrête ici le démarrage : le service n'écoute pas, et toutes les erreurs sont listées.
	PROCEDURE FinInitialisation()
		oLecture est un cEbLectureEnvReelle
		oSortie  est un cEbSortieJournalConsole
		oHorloge est un cEbHorlogeSysteme
		oApp     est un cEbApplication(oLecture, oSortie, oHorloge)
		oBase    est un cEbServiceBase("sqlite")
		oApp.Ajoute(oBase)
		cEbServiceApplication.Definit(oApp)
		cEbServiceApplication.Application().Démarre()
	FIN

	PROCEDURE Fermeture()
		cEbServiceApplication.Arrête()
	FIN

	// Une route qui échoue : le détail va au journal, le client reçoit un JSON sans rien d'interne.
	PROCEDURE surErreur()
		cEbServiceApplication.Application().Journal().Erreur("Erreur dans une route : " + ExceptionInfo(errMessage))
		MoiMême..Réponse..CodeÉtat    = httpErreurServeur
		MoiMême..Réponse..TypeContenu = "application/json"
		MoiMême..Réponse..Corps       = `{"code":"erreur_interne","message":"Une erreur interne est survenue."}`
	FIN

	// GET /api/health : 200 si l'application et ses composants (la base) répondent, 503 sinon.
	Sante est une OpérationHTTP
		PROPRIETES
			Méthode  = httpGet
			Chemin   = ["health"]
			Réponses = [httpOK, httpServiceIndisponible]
			CodeÉtat = httpOK
		FIN
		PROCEDURE surRequête() : chaîne
			MoiMême..Réponse..TypeContenu = "application/json"
			oSante est un cEbSante = cEbServiceApplication.Application().Sante()
			SI PAS oSante.Saine() ALORS
				MoiMême..Réponse..CodeÉtat = httpServiceIndisponible
			FIN
			MoiMême..Réponse..Corps = oSante.Corps()
			RENVOYER ""
		FIN
	FIN
FIN
```

L'argument de `cEbServiceBase(…)`, ici `"sqlite"`, est le fournisseur de base : le même que dans `ebony.conf` (`sqlite`, `postgresql` ou `hfsql`). La base est un **composant** de l'application : sans les deux lignes `oBase` et `oApp.Ajoute(oBase)`, l'application démarre quand même, sans base, et `GET /api/health` répond `{"statut":"ok"}` sans parler de base. Un service généré par `ebony new` contient aussi une route d'accueil `GET /api` ; ajoutez-la si vous la voulez.

Si votre projet a déjà un `ServiceREST`, vous pouvez y ajouter `FinInitialisation` et `Fermeture` au lieu de créer un second service : une seule application est partagée par tous les contrôleurs.

**Sans ce service, les contrôleurs générés ne fonctionnent pas** : `/api/health` n'existe pas et même un jeton valable est refusé (401), parce que la vérification du jeton a besoin de l'application démarrée.

## 3. Écrire une ressource et lancer

```powershell
ebony make migration CreeProduits --champs 'id:entier*,nom:texte,prix:reel' --table produits
ebony make resource Produit --champs 'id:entier*,nom:texte,prix:reel' --table produits
ebony migrate
ebony token create essai
owl serve --port 8080
```

Puis, avec le secret du jeton :

```powershell
curl.exe -s http://127.0.0.1:8080/api/health                                       # {"statut":"ok","base":"ok"}
curl.exe -s -H "Authorization: Bearer eb_…" http://127.0.0.1:8080/api/produits     # []
curl.exe -s -i http://127.0.0.1:8080/api/produits                                  # 401, sans jeton
```

La suite est celle des [premiers pas](premiers-pas.md) : les couches sont décrites dans [le chemin d'une requête](architecture.md).

## Ce qui n'est pas essayé

Un projet OWL réel avec ses propres services et classes (seul un projet vide créé par `owl new projet` l'a été), l'ajout de `FinInitialisation` à un `ServiceREST` déjà présent (proposé plus haut, non rejoué), `--base postgresql` après `init`, et Linux.
