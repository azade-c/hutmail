# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Vendored stylesheets live outside app/assets/stylesheets on purpose:
# `stylesheet_link_tag :app` emits a tag for every file in there, and Leaflet's
# CSS has no business loading on pages without a map.
Rails.application.config.assets.paths << Rails.root.join("vendor/assets/stylesheets")
