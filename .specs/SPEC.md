# HutMail 🦫

> La hutte du castor — là où le courrier est trié et stocké.

## Contexte

Des navigateurs ("les Castors") partent en tour du monde en voilier pour ~18 mois. Leur seul lien avec le monde : une radio BLU (Bande Latérale Unique / SSB) via le réseau **SailMail**, et en backup un téléphone satellite **Iridium**.

### Contraintes de bande passante

- **BLU/SailMail** : ~200 ko/jour, 90 min/semaine glissante, protocole PACTOR (compression Huffman intégrée)
- **Iridium** : ~400 kbps mais 1.5€/min (backup uniquement)
- **Airmail** : logiciel Windows côté bateau, pas de filtrage IMAP, tout ce qui arrive est téléchargé
- **Limite par message** : 35 ko max (SailMail)

### Le problème

Pas de filtrage côté bateau : un spam ou un gros mail peut épuiser le crédit radio. Il faut un "facteur à terre" qui filtre, agrège et transmet intelligemment.

## Solution : HutMail

Une application **Ruby on Rails** qui joue le rôle de facteur automatisé côté terre.

### Architecture

```
[Boîtes mail des Castors]     [Monde extérieur]
        |                            |
        v                            v
   IMAP/POP3                      SMTP
        |                            |
        v                            v
  +----------------------------------+
  |           HutMail (Rails)        |
  |                                  |
  |  - Agrégation entrante          |
  |  - Dispatch sortant             |
  |  - Interface web validation     |
  |  - CLI par email (commandes)    |
  +----------------------------------+
        |                    ^
        v                    |
     SMTP                  SMTP
        |                    |
        v                    |
  [SailMail: callsign@sailmail.com]
        |                    ^
        | PACTOR (radio)     |
        v                    |
  [Bateau - Airmail]  ------+
```

### Flux entrant (monde → bateau)

#### Étape 1 : Collecte et filtrage automatique

1. Cron récupère les boîtes IMAP des Castors à intervalles réguliers
2. Filtrage par règles configurables :
   - Whitelist/blacklist d'expéditeurs
   - Taille max par message
   - Mots-clés prioritaires ou bloqués
   - Priorité par expéditeur (famille > newsletter)
3. Les messages filtrés sont stockés en attente

#### Étape 2 : Screener (résumé léger envoyé au bateau)

Le bateau reçoit d'abord un **screener** — un résumé ultra-compact de ce qui attend :

```
=== SCREENER 15/02 ===
#1 bob@example.com | "Re: Horta" | 0.8 ko | Confirme rdv mardi au port
#2 maman@famille.fr | "Nouvelles" | 1.2 ko | Demande photos, raconte Noël
#3 banque@credit.fr | "Relevé mensuel" | 3.1 ko | Relevé de compte janvier
#4 newsletter@voile.fr | "Actus voile" | 8.2 ko | Vendée Globe résultats
TOTAL en attente : 13.3 ko (4 messages)
===
```

Le résumé IA condense chaque message en une ligne (~10 mots). Le screener pèse quelques centaines d'octets.

#### Étape 3 : Sélection depuis le bateau

Le bateau répond avec les numéros des messages à recevoir :

```
===CMD===
GET 1 2
DROP 3 4
===END===
```

#### Étape 4 : Envoi des messages sélectionnés

Les messages demandés sont strippés (HTML → texte brut, pièces jointes virées, signatures nettoyées) et agrégés en un seul mail compact envoyé à l'adresse SailMail.

**Mode automatique :** si le bateau ne répond pas au screener dans un délai configurable, les règles de priorité s'appliquent automatiquement (ex: famille = toujours envoyer, newsletter = dropper).

#### Pas de facteur humain

Tout est automatisé par les règles. L'interface web sert à configurer les règles avant le départ et à monitorer, pas à valider chaque envoi manuellement.

### Flux sortant (bateau → monde)

1. Réception du mail agrégé depuis l'adresse SailMail (ActionMailbox)
2. Parsing du format structuré :
   ```
   ===MSG bob@example.com===
   On arrive mardi à Horta
   ===MSG famille@castors.fr===
   Tout va bien, 15 nœuds de vent
   ```
3. Dispatch via SMTP depuis les comptes email appropriés
4. Log de ce qui est parti

### CLI par email (commandes depuis le bateau)

Les Castors peuvent envoyer des commandes au serveur :

```
===CMD===
SEND bob@example.com "On arrive mardi"
PAUSE 3d          — stopper l'agrégation (escale, wifi dispo)
RESUME            — reprendre
STATUS            — recevoir un résumé (messages en attente, ko utilisés)
WHITELIST add bob@example.com   — gérer les expéditeurs prioritaires
URGENT famille@castors.fr "Tout va bien"  — envoi immédiat
===END===
```

### Interface web

- **Dashboard** : messages en attente, envoyés, reçus, budget ko consommé/restant
- **Règles** : configuration des filtres, priorités, whitelist/blacklist
- **Comptes** : boîtes IMAP à surveiller, comptes SMTP pour l'envoi
- **Screener** : preview du prochain screener à envoyer
- **Historique** : log complet des échanges
- **Monitoring** : pas de validation manuelle, mais visibilité sur ce que fait le système

## Décisions techniques

### Compression

- **V1 : texte brut** — pas de compression applicative. PACTOR compresse déjà sur la liaison radio (~50-60%). Le gain d'une pré-compression (zlib ~35%) ne justifie pas la complexité côté bateau.
- **V2 (si nécessaire)** : zlib côté Rails + page HTML autonome avec pako.js pour décompresser côté bateau, ou petit compagnon Windows qui surveille le dossier Airmail.

### Format des messages

- Texte brut, délimiteurs simples lisibles par un humain
- Pas de JSON, pas de binaire — si le script plante, le message reste lisible dans Airmail

### Stack

- **Ruby on Rails** (dernière version stable)
- **ActionMailbox** pour la réception des mails entrants
- **ActiveJob** + cron pour l'agrégation périodique
- **SQLite ou PostgreSQL** pour le stockage

### Côté bateau

- **V1** : rien à installer. Texte brut lisible directement dans Airmail.
- **V2** : compagnon Windows (.exe) ou page HTML autonome pour compression/décompression automatique.

## Nom

**HutMail** — la hutte (lodge) du castor. Là où le courrier arrive, est filtré et stocké en sécurité. Entrée protégée (sous l'eau), intérieur au sec. Clin d'œil à Hotmail.

## État du marché

Aucune solution existante identifiée pour le rôle de "facteur à terre" automatisé. Les navigateurs font ça manuellement depuis 20 ans. **pyAirmail** (GitHub: SailingTools) est un remplacement d'Airmail côté bateau en Python, mais ne couvre pas le relaying côté terre.

Potentiel open source : des milliers de bateaux en tour du monde chaque année ont ce problème.

