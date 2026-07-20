# frozen_string_literal: true

class RecordAuditTrailReport < BaseReportOld
  ACTIVE_BG = 'D4EDDA'.freeze
  REMOVED_BG = 'F8D7DA'.freeze
  SUMMARY_BG = 'E8F4FD'.freeze

  def self.build(entity_configuration, form, results)
    new(entity_configuration, form).build(results)
  end

  def build(results)
    @results = Array(results)
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
      executive_summary
      legend_section
      results_sections
    end
  end

  def translation_scope
    'reports.record_audit_trail_report'.freeze
  end

  private

  attr_reader :results, :summary_stats

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
        make_cell(content: t(:summary_removed), size: 9, font_style: :bold, align: :center, background_color: REMOVED_BG),
        make_cell(content: t(:summary_no_audit), size: 9, font_style: :bold, align: :center, background_color: SUMMARY_BG)
      ],
      [
        make_cell(content: summary_stats[:total].to_s, size: 14, font_style: :bold, align: :center),
        make_cell(content: summary_stats[:active].to_s, size: 14, font_style: :bold, align: :center),
        make_cell(content: summary_stats[:removed].to_s, size: 14, font_style: :bold, align: :center),
        make_cell(content: summary_stats[:no_audit].to_s, size: 14, font_style: :bold, align: :center)
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
      text t(:empty), size: 10, style: :italic
      return
    end

    removed_results = results.reject { |result| result[:record_exists] }
    active_results = results.select { |result| result[:record_exists] }

    render_results_group(t(:removed_section_title), removed_results, REMOVED_BG) if removed_results.present?
    render_results_group(t(:active_section_title), active_results, ACTIVE_BG) if active_results.present?
  end

  def render_results_group(section_title, group_results, status_bg)
    start_new_page if cursor < 80

    text section_title, size: 11, style: :bold
    move_down 4

    grouped_by_type(group_results).each do |record_type_label, type_results|
      start_new_page if cursor < 60

      text record_type_label, size: 10, style: :bold
      move_down 4

      table_data = [results_table_headers]

      type_results.each do |result|
        table_data << results_table_row(result, status_bg)
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
      make_cell(content: t('columns.occurred_on'), font_style: :bold, align: :center, width: 55),
      make_cell(content: t('columns.record'), font_style: :bold, align: :center),
      make_cell(content: t('columns.status'), font_style: :bold, align: :center, width: 55),
      make_cell(content: t('columns.verdict'), font_style: :bold, align: :center, width: 130),
      make_cell(content: t('columns.history'), font_style: :bold, align: :center, width: 120)
    ]
  end

  def results_table_row(result, status_bg)
    occurred_on = if result[:primary_at].present?
                    I18n.l(result[:primary_at], format: :compressed)
                  else
                    I18n.l(result[:occurred_on])
                  end

    status_label = result[:record_exists] ? t(:status_active) : t(:status_removed)
    bg_color = result[:record_exists] ? ACTIVE_BG : REMOVED_BG

    [
      make_cell(content: occurred_on, size: 8, width: 55),
      make_cell(content: result[:label].to_s, size: 8),
      make_cell(content: status_label, size: 8, align: :center, width: 55, background_color: bg_color),
      make_cell(content: result[:verdict].to_s, size: 8, width: 130),
      make_cell(content: format_history(result), size: 7, width: 120)
    ]
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
      removed: 0,
      no_audit: 0,
      by_type: {}
    }

    results.each do |result|
      if result[:record_exists]
        stats[:active] += 1
      else
        stats[:removed] += 1
      end

      stats[:no_audit] += 1 if result[:events].blank? && result[:record_exists]

      type_label = result[:record_type_label]
      stats[:by_type][type_label] ||= { active: 0, removed: 0 }

      if result[:record_exists]
        stats[:by_type][type_label][:active] += 1
      else
        stats[:by_type][type_label][:removed] += 1
      end
    end

    stats
  end

  def executive_summary_text
    if results.blank?
      return t(:summary_empty)
    end

    if summary_stats[:removed].positive? && summary_stats[:active].zero?
      return t(:summary_all_removed, removed: summary_stats[:removed], total: summary_stats[:total])
    end

    if summary_stats[:removed].positive?
      return t(
        :summary_mixed,
        active: summary_stats[:active],
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
