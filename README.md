# À table — menus scolaires

Application iPhone native SwiftUI et application web pour lire les menus scolaires par ville. Montmagny (95360) et Argenteuil (95100) sont intégrées. Application indépendante, sans reprise du code, des images ou de la marque Foodi.

## Dans cette version

- Menus réels via l'API publique Foodi, sans compte de consultation.
- Tableau hebdomadaire horizontal et lecture par jour. Alternatives conservées séparément, entrées/plats/accompagnements/laitages/desserts/goûters regroupés.
- Rouge pour les noms de plats identifiés comme contenant de la viande ; vert pour les noms identifiés comme végétariens ou poisson ; catégorie inconnue conservée. Classification indicative et correction personnelle possible par plat. Aucune classification ne garantit l'absence d'allergène.
- Détails des allergènes et labels renvoyés par Foodi.
- Actualisation manuelle et cache local horodaté. Une donnée vide réussie remplace l'ancien menu. Un cache de moins d'une heure évite un appel répété. Les données embarquées réelles du 9 septembre 2026 servent de secours initial, toujours signalé comme copie.
- Accès au programme de la mairie pour les dates sans menu disponible.
- Zones de sécurité iOS, Dynamic Type, modes clair/sombre, portrait et paysage. Mode Jour automatique pour les tailles de texte d'accessibilité.
- Écrans Parents, commentaires par date, compte, signalement et blocage reliés à Supabase dans les builds configurés.
- Sélection de Montmagny ou Argenteuil dans l'application iPhone. Argenteuil propose les menus maternels ou élémentaires.

## Application web et Vercel

Le dossier `web/` contient l'application Next.js responsive. Elle lit Montmagny via Foodi et extrait les menus élémentaires ou maternels depuis les PDF officiels d'Argenteuil. Le registre `web/lib/cities.ts` permet d'ajouter une ville avec son connecteur. La tâche Vercel vérifie les sources chaque jour ouvré.

Configurer sur Vercel le dossier racine `web` et les variables `NEXT_PUBLIC_SUPABASE_URL` et `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Ne jamais utiliser la clé `service_role` dans le navigateur. Le domaine acheté chez Amen pourra ensuite être rattaché au projet Vercel par les enregistrements DNS indiqués par Vercel.

L'IPA utilise l'adresse de production Vercel pour récupérer les PDF officiels d'Argenteuil déjà convertis en menus structurés par l'application web.

## IPA non signé via GitHub

Le workflow `.github/workflows/ios-unsigned.yml` génère le projet avec XcodeGen, compile en Release pour appareil iOS avec la signature désactivée, puis crée `Payload/ATable.app` dans `ATable-Montmagny-unsigned.ipa`.

Il n'utilise ni compte Apple Developer, ni certificat, ni secret de signature. L'IPA doit ensuite être signé par votre méthode d'installation. Aucun profil de provisioning n'est intégré.

Dans **Actions → iPhone - IPA non signe**, lancer **Run workflow**. L'artefact **ATable-Montmagny-unsigned** contient l'IPA et son SHA-256. Les artefacts expirent après 30 jours ; relancer le workflow ou conserver une copie. Aucun envoi automatique à l'App Store.

L'étape de validation exécute des tests unitaires et de navigation sur le simulateur iPhone 17, puis capture les écrans sur iPhone 17, iPhone 17 Pro et iPhone 17 Pro Max. Ces captures sont des exécutions de la véritable application avec les menus embarqués, pas des maquettes. Elles ne remplacent pas un essai sur appareil physique.

## Ouvrir le projet sur Mac

```sh
brew install xcodegen
xcodegen generate
open ATable.xcodeproj
```

Le déploiement minimal est iOS 17.0. Le workflow utilise l'image `macos-26` et sa version stable de Xcode. Aucun framework tiers iOS n'est requis.

## Activer l'espace parents

1. Créer un projet Supabase, appliquer `backend/schema.sql`, puis `backend/migrations/002_multicity_notifications.sql`.
2. Activer la confirmation des adresses e-mail et configurer l'envoi de mails dans Supabase.
3. Ajouter les variables GitHub Actions `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY`, puis recompiler. Utiliser seulement la clé publiable/anon, **jamais service_role**.
4. Les comptes utilisent Supabase Auth ; les sessions sont stockées dans le trousseau iOS. Les messages ne sont visibles qu'aux utilisateurs connectés. La sécurité par ligne limite les insertions/suppressions à leur auteur et masque les participants bloqués. Les signalements doivent être traités par le gestionnaire dans Supabase (`hidden=true` pour masquer un message).
5. Avant ouverture réelle : tester avec deux comptes séparés les droits d'accès et la suppression de compte, attribuer un responsable de modération et configurer le parcours de récupération de mot de passe et les mentions de confidentialité.

Le backend est commun aux clients iPhone, web et au futur client Android.

## Sources

- API vérifiée : `https://api.foodi.fr/graphql`, point de restauration `UG9zOjM4ODg1ODg=`.
- [Mairie de Montmagny](https://www.villedemontmagny.fr/enfance/le-periscolaire/la-restauration-scolaire/) : les corrections de menus sont mises à jour dans Foodi.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) et [images des runners GitHub](https://github.com/actions/runner-images).

Les disponibilités futures et quotas de l'API Foodi ne sont pas garantis. Les noms de plats ne donnent pas toujours leur composition complète.
