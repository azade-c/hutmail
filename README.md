# HutMail 🦫

> La hutte du castor — relay email intelligent pour navigateurs en haute mer.

Relay email automatisé côté terre pour les marins qui communiquent par radio BLU (SailMail/Winlink). Agrège, filtre et transmet les emails dans les contraintes de bande passante extrêmes (~200 ko/jour).

## Le problème

En mer, pas de Wi-Fi. La radio BLU offre ~1-5 kbps avec un crédit limité. Un seul spam peut épuiser la connexion du jour. Jusqu'ici, la solution était un "facteur" humain à terre qui triait le courrier manuellement.

HutMail automatise tout ça : des règles configurables filtrent, agrègent et transmettent — sans intervention humaine.

## Comment ça marche

- **Règles de filtrage** : whitelist/blacklist, taille max, mots-clés, priorités par expéditeur
- **Screener** : le bateau reçoit d'abord un résumé léger (expéditeur, sujet, taille, résumé IA) et choisit quoi télécharger
- **Agrégation** : les messages validés sont strippés (texte brut uniquement) et bundlés en un seul mail compact
- **Dispatch sortant** : parse les messages du bateau et les envoie aux bons destinataires
- **Commandes par email** : le bateau pilote le serveur à distance (modifier les règles, pause, status...)

## Stack

Ruby on Rails • ActionMailbox • ActiveJob

---

*Projet né pour "les Castors" — et peut-être utile à toute la communauté des navigateurs au long cours.*
