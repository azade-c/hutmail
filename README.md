# HutMail 🦫

> La hutte du castor — relay email intelligent pour navigateurs en haute mer.

Facteur automatisé côté terre pour les marins qui communiquent par radio BLU (SailMail/Winlink). Agrège, filtre et transmet les emails dans les contraintes de bande passante extrêmes (~200 ko/jour).

## Le problème

En mer, pas de Wi-Fi. La radio BLU offre ~1-5 kbps avec un crédit limité. Un seul spam peut épuiser la connexion du jour. HutMail joue le rôle du "facteur à terre" : il trie le courrier et n'envoie que l'essentiel.

## Comment ça marche

- **Entrée** : récupère les boîtes IMAP, strip le superflu, agrège en un seul mail texte brut
- **Sortie** : parse les messages du bateau et les dispatche aux bons destinataires
- **Commandes** : le bateau peut piloter le serveur par email (pause, status, whitelist...)
- **Interface web** : validation humaine avant envoi, dashboard, estimation du poids

## Stack

Ruby on Rails • ActionMailbox • ActiveJob

---

*Projet né pour "les Castors" — et peut-être utile à toute la communauté des navigateurs au long cours.*
