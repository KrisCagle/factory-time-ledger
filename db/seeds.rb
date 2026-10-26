# Demo data so you can click through without connecting anything. The data
# itself is built by DemoData::Loader (app/services/demo_data/loader.rb).
#
# Loaded automatically when bin/setup creates a new database, or by
# bin/setup --reset. Skipped if the database already has tickets, so it never
# mixes demo data into real data. Remove it any time from Settings.

if WorkItem.exists?
  puts "Database already has tickets; skipping demo data."
else
  puts "Loading demo data..."
  result = DemoData::Loader.call
  puts "Demo data loaded: #{result[:tickets]} tickets, #{result[:batches]} batches, #{result[:spans]} attention spans, #{result[:drafts]} drafts."
  puts "The previous weekday (#{result[:full_day]}) has the full demo day."
end
