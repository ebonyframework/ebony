import { defineConfig } from 'vitepress'

const owlGrammar = {
  name: 'owl',
  scopeName: 'source.owl',
  patterns: [
    { name: 'comment.line.double-slash.owl', match: '//.*$' },
    // Une chaîne OWL n'a pas d'échappement : elle va du guillemet au guillemet suivant. L'accent grave ouvre une chaîne multi-lignes.
    { name: 'string.quoted.double.owl', begin: '"', end: '"' },
    { name: 'string.quoted.other.owl', begin: '`', end: '`' },
    { name: 'constant.language.owl', match: '(?i)\\b(Vrai|Faux|Null)\\b' },
    { name: 'constant.numeric.owl', match: '\\b\\d+(\\.\\d+)?\\b' },
    { name: 'storage.type.owl', match: '(?i)\\b(entier|chaîne|booléen|réel|tableau|JSON|date|dateheure|heure|Structure|Énumération)\\b' },
    {
      name: 'keyword.control.owl',
      match: '(?i)\\b(SI|ALORS|SINON|FIN|SELON|CAS|AUTRE|POUR|À|TOUT|DE|DANS|TANTQUE|BOUCLE|FAIRE|SORTIR|CONTINUER|RENVOYER|RETOUR|QUAND|EXCEPTION|ENFIN|est|sont|un|une|par|PROCEDURE|FONCTION|CONSTANTE|GLOBALE?|PUBLIQUE?|PRIVÉ|PROTÉGÉ|Classe|Hérite|Interface|implemente|Constructeur|PAS|ET|OU|MODULO|PROPRIETES|MoiMême)\\b'
    }
  ]
}

// Le site de documentation d'Ebony. Les pages sont les fichiers Markdown de docs/ ; seuls les guides (docs/guides/) et la page d'accueil sont publics.
export default defineConfig({
  lang: 'fr-FR',
  title: 'Ebony',
  description: "Le framework d'applications pour le langage OWL : des projets structurés, générés par une commande.",
  // Le site est publié à https://ebonyframework.github.io/ebony/ : « base » doit être le nom du dépôt.
  base: '/ebony/',
  cleanUrls: true,
  // Une page ou un lien mort fait échouer la construction : c'est voulu (les liens de la doc sont vérifiés).
  ignoreDeadLinks: false,
  // Ce qui n'est pas une page du site : les documents du dépôt de développement (absents du dépôt public) et l'index des guides.
  srcExclude: ['architecture/**', 'decisions/**', 'rapports-neowl/**', 'releases/**', 'securite/**', 'guides/README.md'],
  // La coloration des exemples OWL : une petite grammaire écrite par nous (commentaires, chaînes, mots-clés, types), faute de grammaire publique à reprendre.
  // Elle vient du catalogue « owl list keywords » ; OWL ne distingue pas les majuscules, d'où (?i). Elle colore l'essentiel, pas tout : un mot qu'elle ignore s'affiche en texte normal.
  markdown: { languages: [owlGrammar] },
  head: [['link', { rel: 'icon', type: 'image/png', href: '/ebony/logo-ebony.png' }]],

  themeConfig: {
    logo: '/logo-ebony.png',
    nav: [
      { text: 'Installation', link: '/guides/installation' },
      { text: 'Premiers pas', link: '/guides/premiers-pas' },
      { text: 'Commandes', link: '/guides/commandes' },
      { text: 'Notes de version', link: 'https://github.com/ebonyframework/ebony/releases' }
    ],
    sidebar: [
      {
        text: 'Pour commencer',
        items: [
          { text: 'Introduction', link: '/guides/introduction' },
          { text: 'Installation', link: '/guides/installation' },
          { text: 'Ebony sous Linux', link: '/guides/linux' },
          { text: 'Premiers pas', link: '/guides/premiers-pas' },
          { text: "Structure d'un projet", link: '/guides/structure' },
          { text: 'Tutoriel : une petite boutique', link: '/guides/tutoriel' },
          { text: 'Adopter Ebony dans un projet existant', link: '/guides/adopter-un-projet' }
        ]
      },
      {
        text: 'Les bases',
        items: [
          { text: 'Configuration', link: '/guides/configuration' },
          { text: 'Ajouter une route', link: '/guides/routes' },
          { text: 'Erreurs', link: '/guides/erreurs' },
          { text: 'Déployer', link: '/guides/deployer' },
          { text: 'Journal', link: '/guides/journalisation' },
          { text: "Jetons d'accès", link: '/guides/token' }
        ]
      },
      {
        text: 'Base de données',
        items: [
          { text: 'Migrations', link: '/guides/migrate' },
          { text: 'Générer : make', link: '/guides/make' }
        ]
      },
      {
        text: 'Concepts',
        items: [
          { text: "Le chemin d'une requête", link: '/guides/architecture' },
          { text: 'Modules et kits', link: '/guides/modules' },
          { text: 'Statut et limites connues', link: '/guides/statut-et-limites' },
          { text: 'Limites et performance', link: '/guides/performance-et-limites' }
        ]
      },
      {
        text: 'Référence',
        items: [
          { text: 'Commandes', link: '/guides/commandes' },
          { text: 'Glossaire', link: '/guides/glossaire' }
        ]
      }
    ],
    socialLinks: [{ icon: 'github', link: 'https://github.com/ebonyframework/ebony' }],
    editLink: {
      pattern: 'https://github.com/ebonyframework/ebony/edit/main/docs/:path',
      text: 'Modifier cette page sur GitHub'
    },
    search: {
      provider: 'local',
      options: {
        translations: {
          button: { buttonText: 'Rechercher', buttonAriaLabel: 'Rechercher' },
          modal: {
            displayDetails: 'Afficher le détail',
            resetButtonTitle: 'Effacer la recherche',
            backButtonTitle: 'Fermer la recherche',
            noResultsText: 'Aucun résultat pour',
            footer: { selectText: 'choisir', selectKeyAriaLabel: 'entrée', navigateText: 'naviguer', navigateUpKeyAriaLabel: 'flèche haut', navigateDownKeyAriaLabel: 'flèche bas', closeText: 'fermer', closeKeyAriaLabel: 'échap' }
          }
        }
      }
    },
    outline: { label: 'Sur cette page', level: [2, 3] },
    docFooter: { prev: 'Page précédente', next: 'Page suivante' },
    darkModeSwitchLabel: 'Apparence',
    sidebarMenuLabel: 'Menu',
    returnToTopLabel: 'Retour en haut',
    langMenuLabel: 'Changer de langue',
    lightModeSwitchTitle: 'Passer au thème clair',
    darkModeSwitchTitle: 'Passer au thème sombre',
    footer: {
      message: 'Publié sous licence MIT. Ebony est un projet indépendant, non affilié à l\'équipe d\'OWL.',
      copyright: 'ElmiraLabs'
    }
  }
})
