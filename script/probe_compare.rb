#!/usr/bin/env ruby
# Diffs two script/probe.rb outputs and prints only the meaningful differences.
#
#   bundle exec ruby script/probe.rb > base.json
#   bundle exec ruby script/probe.rb > head.json     # from the other tree
#   ruby script/probe_compare.rb base.json head.json
#
# Exits 0 when the two trees are behaviourally identical, 1 otherwise, so it can
# gate an upgrade. Body digests are directly comparable because probe.rb already
# normalises the unstable parts (timestamps, object ids, bcrypt salts, sprockets
# asset digests) before hashing.
require 'json'

base = JSON.parse(File.read(ARGV[0]))
head = JSON.parse(File.read(ARGV[1]))
fail "usage: #{$PROGRAM_NAME} base.json head.json" unless base && head

def key(s) = [s['path'], s['fmt']]
def samples(d) = d['get_samples'].to_h { |s| [key(s), s] }

failures = []

if base['routes'] != head['routes']
  failures << 'routes differ'
  b = base['routes'].map { |r| "#{r['verb']} #{r['path']} #{r['name']}" }
  h = head['routes'].map { |r| "#{r['verb']} #{r['path']} #{r['name']}" }
  (b - h).each { |x| puts "  route only in base: #{x}" }
  (h - b).each { |x| puts "  route only in head: #{x}" }
else
  puts "routes: identical (#{base['routes'].size})"
end

bs, hs = samples(base), samples(head)
missing = bs.keys - hs.keys
extra   = hs.keys - bs.keys
failures << 'sample set differs' unless missing.empty? && extra.empty?
puts "samples: #{bs.keys.size} base / #{hs.keys.size} head" if missing.empty? && extra.empty?
missing.each { |k| puts "  sample only in base: #{k.join(' ')}" }
extra.each   { |k| puts "  sample only in head: #{k.join(' ')}" }

%i[status ctype error loc].each do |f|
  diffs = (bs.keys & hs.keys).select { |k| bs[k][f.to_s] != hs[k][f.to_s] }
  next if diffs.empty?
  failures << "#{f} differs"
  diffs.first(20).each { |k| puts "  #{f}: #{k.join(' ')} #{bs[k][f.to_s].inspect} -> #{hs[k][f.to_s].inspect}" }
end

digest_diffs = (bs.keys & hs.keys).select do |k|
  bs[k]['digest'] != hs[k]['digest']
end
unless digest_diffs.empty?
  failures << "body digest differs (#{digest_diffs.size} pages)"
  digest_diffs.first(30).each { |k| puts "  body changed: #{k.join(' ')}" }
end

if base['ddl'] == head['ddl']
  puts 'ddl: identical'
else
  failures << 'ddl differs'
  bd, hd = base['ddl'], head['ddl']
  (bd - hd).each { |x| puts "  ddl only in base: #{x[0, 120]}" }
  (hd - bd).each { |x| puts "  ddl only in head: #{x[0, 120]}" }
end

if base['probes'] == head['probes']
  puts 'probes: identical'
else
  failures << 'model probes differ'
  (base['probes'].keys | head['probes'].keys).each do |k|
    next if base['probes'][k] == head['probes'][k]
    puts "  #{k}: #{base['probes'][k].to_s[0, 160].inspect} -> #{head['probes'][k].to_s[0, 160].inspect}"
  end
end

puts "versions: base rails #{base['rails_version']} ruby #{base['ruby_version']}" \
     " | head rails #{head['rails_version']} ruby #{head['ruby_version']}"
puts failures.empty? ? 'RESULT: identical' : "RESULT: #{failures.size} difference(s)\n  - #{failures.join("\n  - ")}"
exit(failures.empty? ? 0 : 1)
