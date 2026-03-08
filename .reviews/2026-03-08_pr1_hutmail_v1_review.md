# Review PR #1 — HutMail V1

**Reviewer:** Huttix 🦫
**Date:** 2026-03-08
**Branch:** pr/1 (7b1134e)
**Scope:** 190 files, ~7600 insertions

---

## ✅ Points forts

1. **Encryption partout.** Passwords IMAP/SMTP, adresses email, corps des messages — tout chiffré via `ActiveRecord::Encryption`. Solide pour des données sensibles.

2. **Format radio bien pensé.** Les IDs `DDmon.BB.N` sont compacts, humainement lisibles, et parsables dans les deux sens. Le screener avec budget est une feature killer.

3. **Robustesse IMAP.** Dedup par `imap_message_id`, `ensure` sur les connexions, rescue granulaire. Ça tiendra.

4. **CSS vanilla avec layers.** Propre, pas de dépendance NPM, léger. Bien pour un dashboard qu'on consulte occasionnellement.

5. **Tests des composants critiques.** Parser, formatter, stripper, ID generator — le cœur métier est testé.

6. **`MailAccount::Collecting` est un bon concern.** Inclus dans le modèle, étend ses capacités, utilise les callbacks. C'est le pattern à suivre.

---

## 🔴 Issues critiques

### 1. Service objects déguisés en concerns

**Fichiers:**
- `app/models/concerns/bundle_builder.rb` — classe standalone
- `app/models/concerns/get_response_builder.rb` — classe standalone
- `app/models/concerns/boat_command_parser.rb` — classe standalone

Ces trois classes sont des **service objects** qui vivent dans `concerns/` mais ne sont pas des concerns. Elles ne sont incluses dans aucun modèle — elles sont instanciées avec `BundleBuilder.new(user)`.

**Convention du projet : fat models + concerns, pas de service objects.**

**Fix proposé :**

- `BundleBuilder` → concern `User::Bundling` inclus dans `User`, avec les méthodes `build_bundle`, `deliver_bundle`, etc. directement sur le user.
- `GetResponseBuilder` → intégré dans le même concern `User::Bundling` (c'est un cas particulier de bundling).
- `BoatCommandParser` → concern `User::BoatCommands` inclus dans `User`, avec `parse_boat_commands(text)`.
- `BundleFormatter` et `MessageStripper` sont OK comme modules utilitaires (pas des service objects, ce sont des fonctions pures sans état).
- `HutmailIdGenerator` est OK comme module utilitaire également.

Exemple de refactor pour BundleBuilder :

```ruby
# app/models/concerns/user/bundling.rb
module User::Bundling
  extend ActiveSupport::Concern

  def build_bundle
    pending = mail_accounts
      .includes(:collected_messages)
      .flat_map { |ma| ma.collected_messages.pending.oldest_first }
    return nil if pending.empty?
    # ... reste de la logique, self = user
  end

  def deliver_bundle(bundle)
    return unless bundle&.status == "draft"
    RelayMailer.send_bundle(bundle).deliver_now
    # ...
  end
end
```

### 2. `resolve_smtp_account` — lookup sur champ chiffré non-déterministe

**Fichier:** `app/models/concerns/boat_command_parser.rb` L154-162

```ruby
previous = CollectedMessage.where(from_address: recipient)
```

`from_address` est chiffré avec `encrypts :from_address` (non-déterministe par défaut). Ce `WHERE` ne trouvera jamais rien — ActiveRecord Encryption non-déterministe ne supporte pas les queries `WHERE`.

**Fix:** Soit passer `from_address` en encryption déterministe (`encrypts :from_address, deterministic: true`), soit stocker un hash de l'adresse dans une colonne séparée pour le lookup.

### 3. `abbreviate_email` référencé mais non défini

**Fichier:** `app/models/concerns/bundle_formatter.rb` L68

```ruby
parts << "(→ #{abbreviate_email(others.first)})"
```

La méthode `abbreviate_email` n'est définie nulle part dans le diff. Ça va crasher à l'exécution quand un message a un seul destinataire autre que la boîte surveillée.

---

## 🟡 Issues modérées

### 4. `budget_remaining` peut être négatif

**Fichier:** `app/models/user.rb` L18-20

```ruby
def budget_remaining
  (daily_budget_kb * 7 * 1024) - budget_consumed_7d
end
```

Si le budget est dépassé, `message_budget` et `screener_budget` deviennent négatifs.

**Fix:** `.clamp(0, Float::INFINITY)` ou early return dans le builder.

### 5. Query fragile dans DashboardController

**Fichier:** `app/controllers/dashboard_controller.rb` L3-7

```ruby
@pending_messages = current_user.mail_accounts
  .joins(:collected_messages)
  .where(collected_messages: { status: "pending" })
  .select("collected_messages.*")
```

Retourne des objets `MailAccount` avec les attributs de `CollectedMessage` via `select`. Les méthodes d'instance de `CollectedMessage` ne seront pas disponibles.

**Fix:**
```ruby
@pending_messages = CollectedMessage.pending
  .joins(:mail_account)
  .where(mail_accounts: { user_id: current_user.id })
  .includes(:mail_account)
  .oldest_first
```

Ou mieux, en fat model : `current_user.pending_messages` via un concern.

### 6. `GetResponseBuilder` ne marque pas les messages IMAP comme lus

Contrairement à `BundleBuilder` qui appelle `mark_imap_read` après envoi.

### 7. `mark_sent` itère avec N+1 queries

**Fichier:** `app/models/concerns/bundle_builder.rb` L64-67

```ruby
bundle.collected_messages.each do |msg|
  msg.update!(status: "sent", sent_at: now)
end
```

**Fix:** `bundle.collected_messages.update_all(status: "sent", sent_at: now)`

Note : `update_all` bypasse les callbacks et l'encryption. Si `status` n'est pas chiffré (ce n'est pas le cas), c'est OK. Mais `sent_at` non plus, donc ça passe.

### 8. `after_create_commit :collect_later` — risque sur credentials invalides

**Fichier:** `app/models/concerns/mail_account/collecting.rb` L4-6

Déclenche automatiquement une collecte IMAP à la création du compte. Si les credentials sont mauvaises, le job crashe. Le job est rescué mais l'UX serait meilleure avec un test de connexion.

---

## 🟢 Issues mineures / suggestions

### 9. `find_by_wildcard` + `.or()` en boucle

Crée des queries SQL de plus en plus complexes avec SQLite. À tester avec plusieurs wildcards.

### 10. Pas de `require "net/imap"` explicite

Rails l'autoload, mais les fichiers qui utilisent `Net::IMAP` directement gagneraient en clarté avec un `require`.

### 11. Réponse aux commandes STATUS non renvoyée au bateau

`RelayPollJob` parse et exécute les commandes, mais `parser.results` ne sont jamais renvoyés. Le STATUS calcule les infos mais ne les envoie pas. TODO implicite pour V2.

---

## 🧪 Tests

Tests non exécutés (pas de Ruby dans la sandbox). Tests présents :

| Fichier | Tests |
|---------|-------|
| `BoatCommandParserTest` | 6 (STATUS, DROP, MSG, comments, multiple, unknown) |
| `BundleFormatterTest` | 4 (format_size, attachments, screener truncation/full) |
| `HutmailIdGeneratorTest` | 6 (generate, sequential, year suffix, parse full/partial) |
| `MessageStripperTest` | 6 (HTML, text pref, signatures FR/EN, whitespace, URLs, empty) |
| `UserTest` | 1 (email normalization) |
| `DashboardControllerTest` | 1 |
| `SessionsControllerTest` | 3 |
| `PasswordsControllerTest` | 5 |

**Tests manquants :**
- `BundleBuilder` (build, deliver, budget overflow)
- `GetResponseBuilder`
- `MailAccountsController` (CRUD)
- `SettingsController`
- `CollectedMessage` validations
- `BoatReply` validations
- `RelayPollJob`

---

## 📦 Gems

- `html2text 0.4.0` ✅
- `email_reply_parser 0.5.11` ✅
- Toutes les dépendances lockées ✅

---

## 🔴 Issue critique #4 — Modèle `Vessel` manquant

Actuellement tout est collé sur `User` : sailmail_address, relay config, budget, mail_accounts, bundles, boat_replies. Mais `User` = celui qui se connecte (le facteur à terre). Le bateau est un concept distinct.

**Modèle proposé :**

```
User (login, auth)
└── vessels[] (via memberships ou HABTM)

Vessel
├── name              ("Alibi")
├── callsign          ("WDE1234")
├── sailmail_address  ("WDE1234@sailmail.com")
├── relay config      (IMAP/SMTP du pont terre-mer)
├── budget            (daily_budget_kb, bundle_ratio)
├── mail_accounts[]
├── bundles[]
└── boat_replies[]
```

**Pourquoi :**
- Un user peut gérer plusieurs vessels (flottille, copains)
- Un vessel peut avoir plusieurs users (proprio + gestionnaire à terre pendant la nav)
- Séparation propre auth vs domaine métier
- 1 callsign SailMail = 1 vessel (c'est la réalité radio)

**Impact :** migration des colonnes de User vers Vessel, table de jointure `memberships` (user_id, vessel_id, role), mise à jour de tous les controllers/concerns/jobs.

---

## 📋 Verdict

**Bloquants avant merge :**
1. 🔴 Extraire le modèle `Vessel` (User ≠ bateau)
2. 🔴 Refactor service objects → concerns (BundleBuilder, GetResponseBuilder, BoatCommandParser)
3. 🔴 Fix lookup sur `from_address` chiffré non-déterministe
4. 🔴 Définir `abbreviate_email` dans BundleFormatter

Le reste en follow-up PRs.
