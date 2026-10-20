# lib/attribution is plain Ruby kept out of autoloading so its tests can run
# without Rails. Load it once here.
require Rails.root.join("lib/attribution/engine").to_s
