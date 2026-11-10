# Attribution::FactoryTime turns the factory's working time into per-ticket
# time for the person running it. Plain Ruby, like Attribution::Engine, so it
# can be tested on its own (test/lib/factory_time_test.rb).
#
# Rules:
#
# 1. A ticket's factory time is when at least one agent run was working on it.
#    Two runs on the same ticket at once count once (their union).
# 2. Time the person already tracked by hand (any ticket) is left out, so the
#    same minute is never logged twice.
# 3. When several tickets were being worked at the same moment:
#      share: true   they share that stretch equally, so the day's total never
#                    exceeds the time that actually passed (the default)
#      share: false  each ticket gets its full time
# 4. Time with no run working on anything isn't counted.
module Attribution
  module FactoryTime
    Run = Struct.new(:work_item_id, :started_at, :ended_at, keyword_init: true)

    # runs:    [Run]
    # window:  the day, as a Range of times
    # exclude: [[start, end], ...] the person's own tracked time
    # Returns { work_item_id => whole seconds }.
    def self.call(runs:, window:, exclude: [], share: true)
      busy = merge(exclude.map { |s, e| clip(s, e, window) }.compact)

      per_item = runs.group_by(&:work_item_id).transform_values do |item_runs|
        intervals = merge(item_runs.filter_map { |r| clip(r.started_at, r.ended_at, window) })
        subtract(intervals, busy)
      end.reject { |_, intervals| intervals.empty? }

      seconds = share ? shared(per_item) : per_item.transform_values { |iv| iv.sum { |s, e| e - s } }
      seconds.transform_values(&:round).select { |_, s| s.positive? }
    end

    # Splits each moment equally among the tickets being worked at that moment.
    def self.shared(per_item)
      totals = Hash.new(0.0)
      points = per_item.values.flatten(1).flat_map { |s, e| [s, e] }.uniq.sort
      points.each_cons(2) do |a, b|
        active = per_item.select { |_, intervals| intervals.any? { |s, e| s <= a && e >= b } }.keys
        next if active.empty?

        share = (b - a).to_f / active.size
        active.each { |id| totals[id] += share }
      end
      totals
    end

    def self.clip(start, finish, window)
      return nil if start.nil? || finish.nil?

      s = [start, window.begin].max
      e = [finish, window.end].min
      e > s ? [s, e] : nil
    end

    def self.merge(intervals)
      intervals.sort_by(&:first).each_with_object([]) do |(s, e), out|
        if out.any? && s <= out.last[1]
          out.last[1] = [out.last[1], e].max
        else
          out << [s, e]
        end
      end
    end

    # Removes the `busy` intervals (merged) from `intervals` (merged).
    def self.subtract(intervals, busy)
      intervals.flat_map do |s, e|
        pieces = [[s, e]]
        busy.each do |bs, be|
          pieces = pieces.flat_map do |ps, pe|
            next [[ps, pe]] if be <= ps || bs >= pe

            [([ps, bs] if bs > ps), ([be, pe] if be < pe)].compact
          end
        end
        pieces
      end
    end
  end
end
