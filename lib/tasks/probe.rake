namespace :probe do
  desc 'Run the deterministic functional probe (writes to the test DB)'
  task :run, [:out] => :environment do |_t, args|
    out = args[:out] || 'tmp/probe-current.json'
    sh "bundle exec ruby script/probe.rb > #{out}", verbose: false
    puts "wrote #{out}"
  end

  desc 'Compare two probe JSON files: rake probe:compare[base.json,head.json]'
  task :compare, [:base, :head] => :environment do |_t, args|
    base, head = args[:base], args[:head]
    abort 'usage: rake probe:compare[base.json,head.json]' unless base && head
    sh "ruby script/probe_compare.rb #{base} #{head}", verbose: false
  end
end
