# Revue garde-rails — HutMail

**Date :** 10 mars 2026
**Référentiel :** [garde-rails](https://github.com/fcatuhe/garde-rails) (RAILS.md + STYLE.md)
**Réviseur :** Huttix 🦫

---

## Résumé

Le code est globalement **bien aligné** avec garde-rails. L'architecture modèle-riche avec concerns, les jobs shallow, les controllers CRUD, l'absence de service objects — tout ça est dans les clous. Il y a quand même des ajustements à faire.

**Légende :** 🔴 Non-conforme | 🟡 Amélioration recommandée | 🟢 Conforme | ℹ️ Note

---

## 1. Concerns — Emplacement des fichiers

🔴 **Les concerns sont dans `app/models/concerns/` au lieu de `app/models/<model>/`**

garde-rails dit clairement :
> Model-specific concerns → `app/models/<model>/` (`MailAccount::Collecting`, `Bundle::Delivering`)

Actuellement :
```
app/models/concerns/mail_account/collecting.rb
app/models/concerns/vessel/commanding.rb
app/models/concerns/vessel/bundling.rb
app/models/concerns/collected_message/presentable.rb
app/models/concerns/collected_message/strippable.rb
app/models/concerns/collected_message/identifiable.rb
app/models/concerns/bundle/composable.rb
```

Devrait être :
```
app/models/mail_account/collecting.rb
app/models/vessel/commanding.rb
app/models/vessel/bundling.rb
app/models/collected_message/presentable.rb
app/models/collected_message/strippable.rb
app/models/collected_message/identifiable.rb
app/models/bundle/composable.rb
```

Le dossier `app/models/concerns/` ne devrait contenir que les concerns **partagés** entre plusieurs modèles (`Taggable`, `Sluggable`, etc.).

---

## 2. Style — Visibility modifiers & indentation

🔴 **Les méthodes privées ne sont pas indentées sous `private` dans les controllers**

STYLE.md impose :
```ruby
private
    def some_private_method
      # ...
    end
```

Certains controllers utilisent le style sans indentation :
```ruby
# MailAccountsController
private

def set_mail_account  # ← pas indenté
```

Les concerns (Collecting, Commanding, Bundling, etc.) utilisent correctement le style indenté ✅, mais les controllers non.

**Fichiers concernés :** `MailAccountsController`, `SettingsController`, `DashboardController`

---

## 3. Style — Conditional returns

🟡 **Guard clauses vs expanded conditionals**

STYLE.md préfère les conditionals élargies aux guard clauses, sauf en début de méthode pour du code non-trivial.

Les guard clauses présentes (`return nil if pending.empty?`, `return if imap_uids.empty?`) sont en début de méthode avec un corps non-trivial — acceptables selon les exceptions du style guide. ✅

---

## 4. Controllers — CRUD only

🟢 **Les controllers respectent les 7 actions CRUD.** Pas d'action custom, pas de routes manuelles `get`/`post`. La route `dashboard` et `home` sont des `show` sur des controllers dédiés — c'est propre.

ℹ️ **Note :** `DashboardController` n'est pas derrière un `resource :dashboard` dans les routes. C'est un `get "dashboard"` manuel. Serait plus propre avec :

```ruby
resource :dashboard, only: :show
resource :home, only: :show
```

---

## 5. Modèles — Schema résiduel sur User

🟡 **User porte encore des colonnes relay/sailmail qui ont été migrées vers Vessel**

Le schema montre que `users` a encore :
- `relay_imap_*`, `relay_smtp_*`
- `sailmail_address`
- `bundle_ratio`, `daily_budget_kb`

Ces colonnes existent aussi sur `vessels` et ne sont plus utilisées côté modèle `User`. Une migration de nettoyage serait bienvenue.

---

## 6. Jobs — Shallow pattern

🟢 **Les jobs sont shallow** et délèguent aux modèles. `CollectJob` appelle `collect_now`, `DeliverJob` fait le boulot minimal. Conforme.

🟡 **`VesselReply::DeliverJob` contient de la logique métier**

```ruby
def perform(reply)
  OutboundMailer.send_reply(reply).deliver_now
  reply.update!(status: "sent", sent_at: Time.current)
rescue => e
  reply.update!(status: "error", error_message: e.message)
end
```

Le job devrait juste appeler `reply.deliver_now` et la logique (envoi + update status + gestion erreur) devrait vivre dans un concern `VesselReply::Deliverable` :

```ruby
module VesselReply::Deliverable
  extend ActiveSupport::Concern

  def deliver_later
    VesselReply::DeliverJob.perform_later(self)
  end

  def deliver_now
    OutboundMailer.send_reply(self).deliver_now
    update!(status: "sent", sent_at: Time.current)
  rescue => e
    update!(status: "error", error_message: e.message)
    Rails.logger.error "VesselReply##{id} delivery failed: #{e.message}"
  end
end
```

---

## 7. Jobs — CollectAllJob / BundleAllJob

🟡 **Ces jobs itèrent sur tous les vessels — la logique de "collect all" pourrait être un class method sur le modèle.**

Pas bloquant, mais plus conforme au pattern "shallow job".

---

## 8. RelayPollJob — Trop de logique dans le job

🔴 **`RelayPollJob#poll_relay` contient ~30 lignes de logique IMAP + parsing**

C'est le cas le plus flagrant de logique métier hors modèle. Tout le contenu de `poll_relay` devrait vivre dans un concern `Vessel::RelayPolling` avec un `poll_relay_now` :

```ruby
class RelayPollJob < ApplicationJob
  def perform
    Vessel.find_each(&:poll_relay_now)
  end
end
```

---

## 9. Callbacks — Usage correct

🟢 **`after_create_commit :collect_later`** sur MailAccount::Collecting — exactement le pattern recommandé.

🟢 **`after_create` pour créer le crew captain** sur Vessel — acceptable.

ℹ️ Pas de mécanisme de suppression (`.suppressed`) pour les imports/seeds. À prévoir si besoin.

---

## 10. Mailers — SMTP delivery config

🟡 **`OutboundMailer` et `RelayMailer` ne configurent pas dynamiquement les paramètres SMTP par compte.**

Actuellement les mailers utilisent `mail(from: ...)` mais le `from` seul ne suffit pas — il faut aussi configurer le serveur SMTP du compte. Sinon tout part par le SMTP par défaut de l'app, pas par le SMTP du mail_account/vessel.

C'est probablement un **bug fonctionnel**, pas juste un point de style.

---

## 11. Tests

🟢 **Minitest + fixtures, pas de RSpec/FactoryBot.** Conforme.

🟡 **Tests controllers quasi absents.** Seuls `sessions_controller_test`, `passwords_controller_test`, `dashboard_controller_test` et `vessels_controller_test` existent. Manquent :
- `mail_accounts_controller_test` (CRUD complet)
- `bundles_controller_test`
- `settings_controller_test`

garde-rails dit : "Controller tests = integration tests. Full HTTP request → response → HTML assertion."

🟡 **Certains model tests sont des stubs** (7 lignes, un seul `assert true`). À étoffer : `bundle_test.rb`, `mail_account_test.rb`, `collected_message_test.rb`, `vessel_reply_test.rb`.

---

## 12. Naming — Domain-driven boldness

🟢 **Les noms de domaine sont bons** : `collect_now`, `build_bundle`, `deliver_bundle`, `strip_mail`, `to_radio_text`, `to_screener_line`. Expressif et lié au domaine marin/radio.

🟡 **`Bundle::Composable`** → `Bundle::Composing` serait plus cohérent avec le pattern `-ing` des autres concerns.

---

## 13. Routes manuelles

🟡 **`get "dashboard"` et `get "home"` sont des routes manuelles.** Préférer `resource :dashboard, only: :show` et `resource :home, only: :show`.

---

## 14. Vessel::Commanding — Taille

🟡 **~180 lignes.** Pas au seuil des 500 LOC, mais le concern fait beaucoup (parsing + exécution de toutes les commandes). Envisager de déléguer à un PORO `Vessel::CommandExecutor` en gardant `parse_and_execute_commands` comme façade.

---

## 15. Conformité générale

| Point | Statut | Détail |
|-------|--------|--------|
| `form_with` | 🟢 | Utilisé partout |
| Migration[8.1] | 🟢 | Toutes les migrations OK |
| `has_many :through` | 🟢 | `users through crews` — pas de HABTM |
| `dependent:` | 🟢 | Déclaré sur toutes les associations |
| Strong params | 🟢 | `require().permit()` partout |
| Encrypted fields | 🟢 | `encrypts` sur les champs sensibles |
| Raw SQL | 🟢 | Aucun SQL brut |
| Fixtures | 🟢 | Monde cohérent (Alibi, captain, gmail, orange) |
| No service objects | 🟢 | Aucun `app/services/` |
| Importmap + Propshaft | 🟢 | Pas de Node/webpack |

---

## Plan d'action (par priorité)

1. 🔴 **Déplacer les concerns** de `concerns/` vers `app/models/<model>/`
2. 🔴 **Extraire la logique de `RelayPollJob`** vers `Vessel::RelayPolling`
3. 🟡 **Extraire la logique de `VesselReply::DeliverJob`** vers `VesselReply::Deliverable`
4. 🟡 **Indenter les méthodes privées** dans les controllers (STYLE.md)
5. 🟡 **Routes `resource`** pour dashboard et home
6. 🟡 **Nettoyer les colonnes orphelines** sur `users`
7. 🟡 **Config SMTP dynamique** dans les mailers (bug potentiel)
8. 🟡 **Ajouter les tests controllers manquants**
9. 🟡 **Étoffer les model tests stubs**
10. 🟡 **Renommer `Composable` → `Composing`**

---

*Revue complète du code source. Rien de cassé, mais des ajustements pour coller au référentiel.*
