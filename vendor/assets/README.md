# Vendored stylesheets

`stylesheets/` is kept out of `app/assets/stylesheets` on purpose:
`stylesheet_link_tag :app` emits one `<link>` per file in that directory, and
these are only needed by a single page. `config/initializers/assets.rb` adds
`vendor/assets/stylesheets` to the Propshaft load path so
`stylesheet_link_tag "leaflet"` resolves. This README sits one level up so
Propshaft does not digest it into `public/assets`.

## leaflet.css — Leaflet 1.9.4 (BSD-2-Clause)

- Source: <https://unpkg.com/leaflet@1.9.4/dist/leaflet.css>
- Companion JS: `vendor/javascript/leaflet.js` (same version, UMD build — there
  is no minified ESM build in 1.9.4, so the track layout loads it with a plain
  `javascript_include_tag` and the Stimulus controller reads the global `L`).
- `images/` holds the five PNGs the stylesheet and the default marker icon
  reference. Propshaft resolves `url(images/…)` against this directory and
  fails the precompile if they are missing, so they stay even though the track
  map draws `circleMarker`s and never loads the default icon.

Upgrading: replace `leaflet.css`, `vendor/javascript/leaflet.js` and `images/`
from the same release, then reload `/track/:token` and check that the layer
switcher icon still renders.
