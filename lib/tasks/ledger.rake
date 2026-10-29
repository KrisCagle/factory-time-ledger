namespace :ledger do
  desc "Remove the demo data loaded by db:seed, keeping real data"
  task remove_demo: :environment do
    counts = DemoData.remove!
    puts "Removed demo data: #{counts.map { |k, v| "#{v} #{k.to_s.tr('_', ' ')}" }.join(', ')}"
  end
end

namespace :scarif do
  desc "Read recently changed work items from Scarif into the ledger"
  task sync: :environment do
    outcome = Scarif::Sync.call
    puts outcome.message
    exit(1) unless outcome.ok
  end
end
