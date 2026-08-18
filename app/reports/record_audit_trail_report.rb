# frozen_string_literal: true

class RecordAuditTrailReport < BaseReportOld
  ACTIVE_BG = 'D4EDDA'.freeze
  REMOVED_BG = 'F8D7DA'.freeze
  SUMMARY_BG = 'E8F4FD'.freeze

  INCOMPLETE_BG = 'FFF3CD'.freeze
  NEIGHBOR_BG = 'FFF8E1'.freeze

  def self.build(entity_configuration, form, diagnostic)
    new(entity_configuration, form).build(diagnostic)
  end

  def build(diagnostic)
    diagnostic = normalize_diagnostic(diagnostic)
    @results = Array(diagnostic[:results])
    @neighbors = Array(diagnostic[:neighbors])
    @calendar = Array(diagnostic[:calendar])
    @phrase = diagnostic[:phrase]
    @allocation = diagnostic[:allocation]
    @summary_stats = compute_summary_stats

    header
    body
    footer

    self
  end

  def title
    t(:title)
  end

  def body
    page_content do
      filters_section
      allocation_section
      phrase_section
      executive_summary
      legend_section
      calendar_section
      neighbors_section
      results_sections
    end
  end

  def translation_scope
    'reports.record_audit_trail_report'.freeze
  end

  private

  attr_reader :results, :summary_stats, :neighbors, :calendar, :phrase, :allocation

  def normalize_diagnostic(diagnostic)
    return diagnostic if diagnostic.is_a?(Hash)

    { results: diagnostic, neighbors: [], calendar: [], phrase: nil, allocation: nil }
  end

  def allocation_section
    return if allocation.blank?
    return unless %w[unlinked missing].include?(allocation[:status])
    return if allocation[:status] == 'missing' && results.blank?

    text I18n.t("record_audit_trails.report.allocation_#{allocation[:status]}_title"), size: 10, style: :bold
    move_down 4
    text allocation_text, size: 9, leading: 1.4
    move_down GAP
  end

  def allocation_text
    if allocation[:status] == 'unlinked'
      extras = []
      extras << I18n.t('services.record_audit_trail_phrase.allocation_left_at', date: I18n.l(allocation[:left_at])) if allocation[:left_at].present?
      extras << I18n.t('services.record_audit_trail_phrase.allocation_discarded_at', date: I18n.l(allocation[:discarded_at].to_date)) if allocation[:discarded_at].present?
      I18n.t(
        'services.record_audit_trail_phrase.allocation_unlinked',
        teacher: allocation[:teacher_name],
        classroom: allocation[:classroom_name],
        details: extras.join(' ')
      )
    else
      I18n.t(
        'services.record_audit_trail_phrase.allocation_missing',
        teacher: allocation[:teacher_name],
        classroom: allocation[:classroom_name]
      )
    end
  end

  def phrase_section
    return if phrase.blank?

    text t(:phrase_title), size: 10, style: :bold
    move_down 4
    text phrase, size: 9, leading: 1.4
    move_down GAP
  end

  def calendar_section
    return if calendar.blank?

    text t(:calendar_title), size: 11, style: :bold
    move_down 4

    table_data = [[
      make_cell(content: t('columns.occurred_on'), font_style: :bold, align: :center, width: 70),
      make_cell(content: t(:calendar_frequency), font_style: :bold, align: :center),
      make_cell(content: t(:calendar_content), font_style: :bold, align: :center)
    ]]

    calendar.each do |row|
      table_data << [
        make_cell(content: I18n.l(row[:date]), size: 8, width: 70),
        make_cell(content: calendar_cell_text(row[:frequency]), size: 8, background_color: calendar_bg(row.dig(:frequency, :status))),
        make_cell(content: calendar_cell_text(row[:content]), size: 8, background_color: calendar_bg(row.dig(:content, :status)))
      ]
    end

    table(table_data, width: bounds.width, header: true) do
      cells.border_width = 0.25
      cells.size = 8
      cells.valign = :top
    end

    move_down GAP
  end

  def calendar_cell_text(cell)
    cell ||= {}
    status = I18n.t("record_audit_trails.report.calendar.#{cell[:status]}", default: cell[:status].to_s)
    label = cell[:label]
    label.present? && label != '—' ? "#{status} — #{label}" : status
  end

  def calendar_bg(status)
    case status
    when 'recorded' then ACTIVE_BG
    when 'incomplete', 'mixed' then INCOMPLETE_BG
    when 'deleted', 'missing' then REMOVED_BG
    else WHITE
    end
  end

  def neighbors_section
    return if neighbors.blank?

    render_results_group(t(:neighbors_title), neighbors, NEIGHBOR_BG, include_mismatch: true)
  end

  def filters_section
    filters_header = make_table_header_cell(t(:filters_header), colspan: 2)

    rows = [
      [filters_header],
      filter_row(t(:unity), unity_label),
      filter_row(t(:teacher), teacher_label),
      filter_row(t(:classroom), classroom_label),
      filter_row(t(:discipline), discipline_label),
      filter_row(t(:period), period_label),
      filter_row(t(:record_types), record_types_label)
    ]

    table(rows, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def filter_row(label, value)
    [
      make_row_header_cell(label, width: 120),
      make_content_cell(value)
    ]
  end

  def executive_summary
    summary_header = make_table_header_cell(t(:summary_header), colspan: 4)

    summary_rows = [
      [summary_header],
      [
        make_cell(content: t(:summary_total), size: 9, font_style: :bold, align: :center, background_color: SUMMARY_BG),
        make_cell(content: t(:summary_active), size: 9, font_style: :bold, align: :center, background_color: ACTIVE_BG),
        make_cell(content: t(:summary_incomplete), size: 9, font_style: :bold, align: :center, background_color: INCOMPLETE_BG),
        make_cell(content: t(:summary_removed), size: 9, font_style: :bold, align: :center, background_color: REMOVED_BG)
      ],
      [
        make_cell(content: summary_stats[:total].to_s, size: 14, font_style: :bold, align: :center),
        make_cell(content: summary_stats[:active].to_s, size: 14, font_style: :bold, align: :center),
        make_cell(content: summary_stats[:incomplete].to_s, size: 14, font_style: :bold, align: :center),
        make_cell(content: summary_stats[:removed].to_s, size: 14, font_style: :bold, align: :center)
      ]
    ]

    table(summary_rows, width: bounds.width) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP

    text executive_summary_text, size: 10, leading: 1.4
    move_down GAP

    return if summary_stats[:by_type].blank?

    type_breakdown_header = make_table_header_cell(t(:summary_by_type), colspan: 3)
    type_rows = [[type_breakdown_header]]

    summary_stats[:by_type].each do |type_label, counts|
      type_rows << [
        make_row_cell(type_label, size: 9),
        make_row_cell(t(:summary_type_active, count: counts[:active]), size: 9, background_color: ACTIVE_BG),
        make_row_cell(t(:summary_type_removed, count: counts[:removed]), size: 9, background_color: REMOVED_BG)
      ]
    end

    table(type_rows, width: bounds.width) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def legend_section
    text t(:legend_title), size: 10, style: :bold
    move_down 4

    t(:legend_items).each do |item|
      text "• #{item}", size: 8, leading: 1.3
    end

    move_down GAP
  end

  def results_sections
    if results.blank?
      text t(:empty), size: 10, style: :italic unless neighbors.present? || calendar.present?
      return
    end

    removed_results = results.select { |result| result_status(result) == 'removed' }
    incomplete_results = results.select { |result| result_status(result) == 'incomplete' }
    active_results = results.select { |result| result_status(result) == 'active' }

    render_results_group(t(:removed_section_title), removed_results, REMOVED_BG) if removed_results.present?
    render_results_group(t(:incomplete_section_title), incomplete_results, INCOMPLETE_BG) if incomplete_results.present?
    render_results_group(t(:active_section_title), active_results, ACTIVE_BG) if active_results.present?
  end

  def render_results_group(section_title, group_results, status_bg, include_mismatch: false)
    start_new_page if cursor < 80

    text section_title, size: 11, style: :bold
    move_down 4

    grouped_by_type(group_results).each do |record_type_label, type_results|
      start_new_page if cursor < 60

      text record_type_label, size: 10, style: :bold
      move_down 4

      table_data = [results_table_headers]

      type_results.each do |result|
        table_data << results_table_row(result, status_bg, include_mismatch: include_mismatch)
      end

      table(table_data, width: bounds.width, header: true) do
        cells.border_width = 0.25
        cells.size = 8
        row(0).font_style = :bold
        row(0).align = :center
        cells.valign = :top
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end

      move_down GAP
    end
  end

  def results_table_headers
    [
      make_cell(content: t('columns.occurred_on'), font_style: :bold, align: :center, width: 50),
      make_cell(content: t('columns.event_at'), font_style: :bold, align: :center, width: 70),
      make_cell(content: t('columns.record'), font_style: :bold, align: :center),
      make_cell(content: t('columns.status'), font_style: :bold, align: :center, width: 55),
      make_cell(content: t('columns.verdict'), font_style: :bold, align: :center, width: 110),
      make_cell(content: t('columns.history'), font_style: :bold, align: :center, width: 100)
    ]
  end

  def results_table_row(result, status_bg, include_mismatch: false)
    pedagogical = if result[:occurred_on].present?
                    I18n.l(result[:occurred_on].to_date)
                  else
                    '—'
                  end

    event_at = if result[:event_at].present?
                 I18n.l(result[:event_at], format: :compressed)
               elsif result[:primary_at].present?
                 I18n.l(result[:primary_at], format: :compressed)
               else
                 '—'
               end

    record_text = result[:label].to_s
    record_text += "\n#{result[:detail]}" if result[:detail].present?
    if include_mismatch && result[:mismatch_reasons].present?
      reasons = Array(result[:mismatch_reasons]).map do |reason|
        I18n.t("services.record_audit_trail_phrase.reasons.#{reason}")
      end.join(', ')
      record_text += "\n#{t(:neighbor_mismatch)}: #{reasons}"
    end

    status_label, bg_color = status_presentation(result, status_bg)

    [
      make_cell(content: pedagogical, size: 8, width: 50),
      make_cell(content: event_at, size: 8, width: 70),
      make_cell(content: record_text, size: 8),
      make_cell(content: status_label, size: 8, align: :center, width: 55, background_color: bg_color),
      make_cell(content: result[:verdict].to_s, size: 8, width: 110),
      make_cell(content: format_history(result), size: 7, width: 100)
    ]
  end

  def result_status(result)
    return result[:status] if result[:status].present?

    result[:record_exists] ? 'active' : 'removed'
  end

  def status_presentation(result, fallback_bg)
    status = result_status(result)

    case status
    when 'incomplete'
      [t(:status_incomplete), INCOMPLETE_BG]
    when 'removed'
      [t(:status_removed), REMOVED_BG]
    else
      [t(:status_active), fallback_bg == NEIGHBOR_BG ? NEIGHBOR_BG : ACTIVE_BG]
    end
  end

  def format_history(result)
    events = Array(result[:events])
    return result[:summary].to_s if events.blank?

    events.map do |event|
      line = I18n.t(
        'services.record_audit_trail_summary.event_line',
        action: event[:action_label],
        datetime: I18n.l(event[:at], format: :compressed),
        user: event[:user_name]
      )
      event[:detail].present? ? "#{line} (#{event[:detail]})" : line
    end.join("\n")
  end

  def grouped_by_type(group_results)
    group_results
      .group_by { |result| result[:record_type_label] }
      .sort_by { |label, _| label }
  end

  def compute_summary_stats
    stats = {
      total: results.size,
      active: 0,
      incomplete: 0,
      removed: 0,
      no_audit: 0,
      by_type: {}
    }

    results.each do |result|
      status = result_status(result)
      case status
      when 'incomplete'
        stats[:incomplete] += 1
      when 'removed'
        stats[:removed] += 1
      else
        stats[:active] += 1
      end

      stats[:no_audit] += 1 if result[:events].blank? && result[:record_exists]

      type_label = result[:record_type_label]
      stats[:by_type][type_label] ||= { active: 0, removed: 0 }

      if status == 'removed'
        stats[:by_type][type_label][:removed] += 1
      else
        stats[:by_type][type_label][:active] += 1
      end
    end

    stats
  end

  def executive_summary_text
    if results.blank?
      return t(:summary_empty)
    end

    if summary_stats[:removed].positive? && summary_stats[:active].zero? && summary_stats[:incomplete].zero?
      return t(:summary_all_removed, removed: summary_stats[:removed], total: summary_stats[:total])
    end

    if summary_stats[:removed].positive? || summary_stats[:incomplete].positive?
      return t(
        :summary_mixed,
        active: summary_stats[:active],
        incomplete: summary_stats[:incomplete],
        removed: summary_stats[:removed],
        total: summary_stats[:total]
      )
    end

    t(:summary_all_active, active: summary_stats[:active], total: summary_stats[:total])
  end

  def unity_label
    Unity.find_by(id: @form.unity_id)&.to_s || t(:all)
  end

  def teacher_label
    Teacher.find_by(id: @form.teacher_id)&.to_s || t(:all)
  end

  def classroom_label
    Classroom.find_by(id: @form.classroom_id)&.to_s || t(:all)
  end

  def discipline_label
    Discipline.find_by(id: @form.discipline_id)&.to_s || t(:all)
  end

  def period_label
    t(:period_content, start_at: format_date(@form.start_at), end_at: format_date(@form.end_at))
  end

  def record_types_label
    @form.selected_record_types.map do |type|
      I18n.t("services.record_audit_trail_summary.record_types.#{type}")
    end.join(', ')
  end

  def format_date(value)
    return value if value.is_a?(String) && value.match?(%r{\d{2}/\d{2}/\d{4}})

    I18n.l(value.to_date)
  rescue StandardError
    value.to_s
  end
end
