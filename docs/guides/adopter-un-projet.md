# Adopter Ebony dans un projet OWL existant

Vous avez déjà un projet OWL (un `projet.owl`) et vous voulez y ajouter Ebony sans repartir de zéro. `ebony init` ajoute la bibliothèque et la configuration sans rien écraser. Il **n'écrit pas** le service REST que `ebony new` génère : c'est lui qui démarre l'application (configuration, journal, base) dont les contrôleurs générés ont besoin. Ce guide montre comment l'ajouter. Le parcours complet a été rejoué sur un projet créé par `owl new projet`, sous Windows avec OWL 1.8.1 et SQLite.

## 1. Ajouter Ebony

À la racine du projet :

```powershell
ebony init
Copy-Item .env.exemple .env
Copy-Item .env.secrets.exemple .env.secrets
```

`ebony init` accepte les mêmes options que `ebony new` (`--base sqlite|postgresql|hfsql`, `--auth [--table …]`), sans nom de projet. Il écrit : `ebony/` (la bibliothèque), `ebony.conf`, `config/env.json`, `.env.exemple` et `.env.secrets.exemple`, `.gitignore`, `README.md` et `AGENTS.md` (consignes pour un assistant de code) s'ils n'existent pas, `app/Composants.owl` (le registre des composants : la base de données y est déclarée), et les migrations et fichiers des modules (la migration des jetons). **Il conserve tout fichier existant**, `projet.owl` compris, et le dit : « Conservés : projet.owl (non modifiés) ». Le projet compile ensuite sans autre changement.

Il termine par une note sur ce qu'il vous reste à faire, ici appeler le registre depuis votre service (étape suivante) :

```text
À faire vous-même :
  - app/Composants.owl liste les composants des modules du projet (…) Votre service doit l'appeler pour les démarrer : dans son FinInitialisation, après la création de oApp, ajoutez « POUR TOUT oFabrique DE boutiqueFabriques() », puis « oApp.Ajoute(oFabrique) » et « FIN » (voir le guide d'adoption).
```

Le nom de la procédure du registre est celui du bloc `est un Projet` de votre `projet.owl` (ici `boutique`), suivi de `Fabriques` : copiez-le tel que la note l'écrit.

## 2. Ajouter le service qui démarre l'application

Créez `app/http/ServiceBoutique.owl` (le nom est libre, il doit être unique dans le projet) :

```owl
ServiceBoutique est un ServiceREST
	PROPRIETES
		UrlBase = ["api"]
	FIN

	// L'application unique est posée dans cEbServiceApplication, pas dans une variable du bloc du service.
	// Les composants (la base de données) viennent du registre app/Composants.owl, que gère Ebony.
	// Une configuration invalide arrête ici le démarrage : le service n'écoute pas, et toutes les erreurs sont listées.
	PROCEDURE FinInitialisation()
		oLecture est un cEbLectureEnvReelle
		oSortie  est un cEbSortieJournalConsole
		oHorloge est un cEbHorlogeSysteme
		oApp     est un cEbApplication(oLecture, oSortie, oHorloge)
		POUR TOUT oFabrique DE boutiqueFabriques()
			oApp.Ajoute(oFabrique)
		FIN
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

Le registre `app/Composants.owl` rend la liste des composants des modules du projet, dans l'ordre de démarrage ; la base de données en est un, avec le fournisseur noté dans `ebony.conf` (`sqlite`, `postgresql` ou `hfsql`). **Ebony gère ce fichier** : quand vous ajoutez un module avec [`ebony add`](ajouter-un-module.md), il le réécrit, et votre service ne change pas. Sans la boucle `POUR TOUT oFabrique DE …`, l'application démarre quand même, sans base, et `GET /api/health` répond `{"statut":"ok"}` sans parler de base. Un service généré par `ebony new` contient aussi une route d'accueil `GET /api` ; ajoutez-la si vous la voulez.

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

## Ajouter un module plus tard

Vous pouvez adopter Ebony sans base de données et en ajouter une ensuite, **sans toucher à votre service** : `ebony init --kit slim` écrit un registre vide, que le service appelle déjà.

```powershell
ebony init --kit slim
# … le service ci-dessus, qui appelle le registre …
ebony add db
```

Avant `ebony add db`, `GET /api/health` répond `{"statut":"ok"}` ; après, `{"statut":"ok","base":"ok"}`, et `app/http/ServiceAtelier.owl` est resté identique octet pour octet : seul le registre est réécrit. Voir [Ajouter un module](ajouter-un-module.md).

## Ce qui n'est pas essayé

Un projet OWL réel avec ses propres services et classes (seuls des projets vides créés par `owl new projet` l'ont été), l'ajout de `FinInitialisation` à un `ServiceREST` déjà présent (proposé plus haut, non rejoué), `--base postgresql` après `init`, et Linux.
