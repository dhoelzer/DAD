# Fails unless every asset path the app emits exists on disk under public/.
#
# config.assets.compile = false means Apache serves assets, not Rails, so a path
# with no file behind it is a 404 in production. The test suite cannot catch
# that: it boots in development, where the pipeline compiles anything on demand.
#
# The coupling this exists to catch is digest/compile. With digest = false the
# helpers emit /assets/application.js, but sprockets-rails 3.x precompile writes
# only digested filenames, so the emitted path has no file behind it and every
# stylesheet and script 404s -- with the whole suite green.
#
# Run after a production precompile:
#   RAILS_ENV=production bundle exec rake assets:precompile
#   RAILS_ENV=production bundle exec ruby script/check_asset_paths.rb
require_relative "../config/environment"

def emitted_paths
  helpers = ActionController::Base.helpers

  # The layout's own tags, resolved through the manifest.
  tags = [helpers.stylesheet_link_tag("application"),
          helpers.javascript_include_tag("application")]
  paths = tags.flat_map { |tag| tag.scan(%r{(?:href|src)="([^"]+)"}).flatten }

  # Assets the compiled CSS pulls in via url(), which the helpers never see.
  Dir["public/assets/application-*.css"].each do |css|
    matches = File.read(css).scan(%r{url\((['"]?)(/assets/[^)'"]+)\1\)})
    paths += matches.map { |groups| groups.last }
  end

  paths.uniq
end

paths = emitted_paths
abort "no asset paths emitted -- did the precompile run?" if paths.empty?

missing = paths.reject { |p| File.file?(File.join("public", p.delete_prefix("/"))) }

if missing.any?
  warn "emitted asset paths with no file under public/:"
  missing.each { |p| warn "  #{p}" }
  exit 1
end

puts "all #{paths.size} emitted asset paths exist on disk"
paths.sort.each { |p| puts "  #{p}" }
