# Attribution::Engine turns one person's attention spans for a day into
# per-ticket time. It is plain Ruby with no Rails dependency, so the rules
# can be tested on their own (see test/lib/attribution_engine_test.rb).
#
# The rules, in order:
#
# 1. Attention is single-threaded. If spans overlap, the span that started
#    later wins and the earlier one is cut off where the later one starts.
# 2. A span on a ticket is direct time for that ticket.
# 3. A span on a batch (no ticket) is batch overhead. Each batch's overhead is
#    split across the batch's tickets by the split rule:
#      :agent_points  weight by Jira agent points (falls back to :agent_time
#                     if any ticket in the batch is unsized)
#      :agent_time    weight by how long agents ran on each ticket (falls back
#                     to :even if any ticket has no agent time)
#      :even          equal shares
# 4. A span with neither a ticket nor a batch is unattributed. It is shown,
#    never drafted to Harvest.
#
# Splits use whole seconds with largest-remainder rounding, so a batch's
# shares always add back up to exactly its overhead.
module Attribution
  Span = Struct.new(:id, :work_item_id, :batch_id, :activity, :started_at, :ended_at, keyword_init: true)
  Item = Struct.new(:id, :batch_id, :agent_points, :agent_seconds, keyword_init: true)
  Line = Struct.new(:work_item_id, :activity, :direct_seconds, :overhead_seconds, keyword_init: true) do
    def total_seconds = direct_seconds + overhead_seconds
  end
  BatchSplit = Struct.new(:batch_id, :requested_rule, :rule_used, :pool_seconds, :shares, keyword_init: true)
  Result = Struct.new(:lines, :unattributed_seconds, :batch_splits, :effective_spans, keyword_init: true) do
    def total_attributed_seconds = lines.sum(&:total_seconds)
  end

  class Engine
    RULES = %i[agent_points agent_time even].freeze

    def self.call(...) = new(...).call

    # Hours for Harvest. rounding_minutes of 0 or 1 means "to the minute";
    # otherwise round to the nearest increment (6 = Harvest's 0.1 hour).
    def self.hours_for(seconds, rounding_minutes: 1)
      minutes = seconds / 60.0
      step = rounding_minutes.to_i
      minutes = (minutes / step).round * step if step > 1
      (minutes / 60.0).round(2)
    end

    def initialize(spans:, items:, rule: :agent_points)
      @spans = spans
      @items = items
      @rule = rule.to_sym
      raise ArgumentError, "unknown split rule #{rule}" unless RULES.include?(@rule)
    end

    def call
      effective = flatten_overlaps(@spans)
      lines = Hash.new { |h, key| h[key] = Line.new(work_item_id: key[0], activity: key[1], direct_seconds: 0, overhead_seconds: 0) }
      pools = Hash.new { |h, batch_id| h[batch_id] = Hash.new(0) }
      unattributed = 0

      effective.each do |span|
        seconds = duration(span)
        next if seconds <= 0

        if span.work_item_id
          lines[[span.work_item_id, span.activity]].direct_seconds += seconds
        elsif span.batch_id
          pools[span.batch_id][span.activity] += seconds
        else
          unattributed += seconds
        end
      end

      splits = pools.map do |batch_id, by_activity|
        members = @items.select { |item| item.batch_id == batch_id }
        if members.empty?
          unattributed += by_activity.values.sum
          next BatchSplit.new(batch_id:, requested_rule: @rule, rule_used: nil, pool_seconds: by_activity.values.sum, shares: {})
        end

        rule_used, weights = weights_for(members)
        by_activity.each do |activity, pool|
          distribute(pool, weights).each do |item_id, seconds|
            lines[[item_id, activity]].overhead_seconds += seconds if seconds.positive?
          end
        end

        total_weight = weights.values.sum.to_f
        shares = weights.transform_values { |w| (w / total_weight).round(4) }
        BatchSplit.new(batch_id:, requested_rule: @rule, rule_used:, pool_seconds: by_activity.values.sum, shares:)
      end.compact

      Result.new(
        lines: lines.values.select { |line| line.total_seconds.positive? },
        unattributed_seconds: unattributed,
        batch_splits: splits,
        effective_spans: effective
      )
    end

    private

      def duration(span) = (span.ended_at - span.started_at).to_i

      # Later-started span wins; the earlier span is cut where it begins.
      def flatten_overlaps(spans)
        sorted = spans.sort_by { |s| [s.started_at, s.id.to_s] }
        sorted.each_with_index.map do |span, index|
          following = sorted[index + 1]
          ended_at = span.ended_at
          ended_at = following.started_at if following && following.started_at < ended_at
          Span.new(**span.to_h, ended_at:)
        end
      end

      def weights_for(members)
        order = case @rule
                when :agent_points then %i[agent_points agent_time even]
                when :agent_time then %i[agent_time even]
                else %i[even]
                end

        order.each do |rule|
          weights = case rule
                    when :agent_points then members.to_h { |m| [m.id, m.agent_points.to_f] }
                    when :agent_time then members.to_h { |m| [m.id, m.agent_seconds.to_f] }
                    else members.to_h { |m| [m.id, 1.0] }
                    end
          return [rule, weights] if weights.values.all?(&:positive?)
        end
      end

      # Largest-remainder split in whole seconds; ties go to the lower id.
      def distribute(pool, weights)
        total = weights.values.sum
        exact = weights.transform_values { |w| pool * w / total }
        floors = exact.transform_values(&:floor)
        leftover = pool - floors.values.sum
        ranked = exact.keys.sort_by { |id| [-(exact[id] - floors[id]), id.to_s] }
        ranked.first(leftover).each { |id| floors[id] += 1 }
        floors
      end
  end
end
