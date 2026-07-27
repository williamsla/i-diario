class PedagogicalTrackingResumeTable
  STEPS = [1, 2, 3, 4].freeze

  Record = Struct.new(
    :classroom,
    :teacher,
    :discipline,
    :frequencies,
    :lesson_plans,
    :content_hours,
    :evaluations,
    :students_without_opinion,
    :pending_steps,
    :pending
  )

  attr_reader :records, :grouped_records, :has_lesson_plan, :has_opinion, :summary

  def initialize(sheet)
    rows = sheet.to_a
    header = rows.first || []
    data_rows = rows[1..-1] || []

    @has_lesson_plan = header[7].to_s.strip.present?
    @has_opinion = header[13].to_s.strip.present?
    @records = data_rows.map { |row| build_record(row) }
    @grouped_records = @records.group_by(&:classroom)
    @summary = build_summary
  end

  def teachers
    @teachers ||= records.map(&:teacher).uniq.sort
  end

  def disciplines
    @disciplines ||= records.map(&:discipline).uniq.sort
  end

  def blank?(value)
    value.blank? || value.to_s.strip == '-' || value.to_s.strip == '0'
  end

  def filled?(value)
    !blank?(value)
  end

  def opinion_alert?(value)
    return false if blank?(value)

    value.to_s.gsub(/\D/, '').to_i.positive?
  end

  def display_value(value)
    blank?(value) ? '—' : value.to_s
  end

  def metric_status(value)
    filled?(value) ? 'done' : 'missing'
  end

  def opinion_status(value)
    opinion_alert?(value) ? 'alert' : 'done'
  end

  private

  def build_record(row)
    frequencies = [row[3], row[4], row[5], row[6]]
    evaluations = [row[9], row[10], row[11], row[12]]
    content_hours = row[8]
    lesson_plans = row[7]
    students_without_opinion = row[13]

    pending_steps = STEPS.select do |step|
      blank?(frequencies[step - 1]) || blank?(evaluations[step - 1])
    end

    pending = pending_steps.any? ||
              blank?(content_hours) ||
              (@has_lesson_plan && blank?(lesson_plans)) ||
              opinion_alert?(students_without_opinion)

    Record.new(
      row[0].to_s,
      humanize_text(row[1]),
      humanize_text(row[2]),
      frequencies,
      lesson_plans,
      content_hours,
      evaluations,
      students_without_opinion,
      pending_steps,
      pending
    )
  end

  def build_summary
    {
      total: records.size,
      pending: records.count(&:pending),
      missing_frequency: records.count { |record| record.frequencies.any? { |value| blank?(value) } },
      missing_evaluation: records.count { |record| record.evaluations.any? { |value| blank?(value) } },
      missing_content: records.count { |record| blank?(record.content_hours) },
      opinion_alerts: @has_opinion ? records.count { |record| opinion_alert?(record.students_without_opinion) } : 0,
      students_without_opinion: @has_opinion ? records.sum { |record| record.students_without_opinion.to_s.gsub(/\D/, '').to_i } : 0,
      classrooms: grouped_records.size
    }
  end

  def humanize_text(value)
    return '' if value.blank?

    text = value.to_s.strip
    if (match = text.match(/\A(.+?)(\s*\(saiu em .+?\))\z/i))
      "#{titlecase_words(match[1])}#{match[2]}"
    else
      titlecase_words(text)
    end
  end

  def titlecase_words(text)
    text.to_s.downcase.gsub(/([[:alpha:]])([[:alpha:]]*)/) do
      "#{Regexp.last_match(1).upcase}#{Regexp.last_match(2)}"
    end
  end
end
