module ApplicationHelper
  # 5400 -> "1h 30m", 300 -> "5m", 0 -> "0m"
  def duration(seconds)
    minutes = (seconds.to_i / 60.0).round
    hours, mins = minutes.divmod(60)
    hours.positive? ? "#{hours}h #{mins.to_s.rjust(2, '0')}m" : "#{mins}m"
  end

  def money(amount) = number_to_currency(amount.to_d, precision: 2)

  def activity_label(activity) = Activity.label(activity)

  def status_pill(status)
    tag.span(status.to_s.humanize, class: "pill pill-#{status.to_s.dasherize}")
  end

  def nav_link(label, path, section)
    tag.a(label, href: path, class: ["nav-link", ("active" if controller_name == section)])
  end

  def rule_label(rule) = rule.to_s.tr("_", " ")

  def day_link(date, label)
    link_to label, url_for(request.query_parameters.merge(date: date.iso8601)), class: "btn btn-ghost"
  end

  # Positions for the Today timeline. Returns [window_start, window_end, bars].
  def timeline_bars(attribution)
    effective = attribution.result.effective_spans.index_by(&:id)
    spans = attribution.spans
    day = attribution.day_range
    times = effective.values.flat_map { |s| [s.started_at, s.ended_at] }
    window_start = [times.min || day.begin + 8.hours, day.begin + 8.hours].min
    window_end = [times.max || day.begin + 18.hours, day.begin + 18.hours].max
    total = (window_end - window_start).to_f

    bars = spans.filter_map do |span|
      eff = effective[span.id]
      next unless eff && eff.ended_at > eff.started_at

      {
        left: ((eff.started_at - window_start) / total * 100).round(3),
        width: [((eff.ended_at - eff.started_at) / total * 100).round(3), 0.4].max,
        kind: span.work_item ? "direct" : (span.batch ? "overhead" : "none"),
        activity: span.activity,
        label: span.target_label,
        title: "#{span.target_label} · #{activity_label(span.activity)} · #{eff.started_at.strftime('%-l:%M')}–#{eff.ended_at.strftime('%-l:%M %p')}"
      }
    end
    [window_start, window_end, bars]
  end
end
