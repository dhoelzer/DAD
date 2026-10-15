# Rails 7.1's Active Storage, Action Text and Action Cable engines each add their
# own JS bundles to the sprockets precompile list; 6.1's engines did not. This app
# uses none of the three -- no active_storage_*/action_text_* tables, no ActionCable
# consumer, no trix in any view -- and those bundles are ES6, which uglifier 2.7
# (the compressor this app has always used) cannot parse: assets:precompile dies
# with "Unexpected token: name (FileChecksum)".
#
# Active Storage and Action Cable are switched off through their own flags. Action
# Text has no flag, so its entries are subtracted in after_initialize -- the only
# point that runs after every engine initializer has appended them.
Rails.application.config.active_storage.precompile_assets = false
Rails.application.config.action_cable.precompile_assets = false

Rails.application.config.after_initialize do |app|
  app.config.assets.precompile -= %w[
    actiontext.js actiontext.esm.js trix.js trix.css
    activestorage activestorage.esm
    actioncable.js actioncable.esm.js
  ]
end
