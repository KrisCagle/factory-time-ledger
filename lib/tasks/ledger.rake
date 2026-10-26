namespace :ledger do
  desc "Remove the demo data loaded by db:seed, keeping real data"
  task remove_demo: :environment do
    counts = DemoData.remove!
    puts "Removed demo data: #{counts.map { |k, v| "#{v} #{k.to_s.tr('_', ' ')}" }.join(', ')}"
  end
end
