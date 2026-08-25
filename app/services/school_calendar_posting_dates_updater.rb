# frozen_string_literal: true

class SchoolCalendarPostingDatesUpdater
  Group = Struct.new(
    :step_number,
    :step_type_description,
    :school_count,
    :classroom_step_count,
    :start_dates,
    :end_dates
  ) do
    def label
      SchoolCalendarPostingDatesUpdater.group_label(step_number, step_type_description)
    end
  end

  class Result
    attr_reader :updated_count, :errors

    def initialize
      @updated_count = 0
      @errors = []
    end

    def add_updated
      @updated_count += 1
    end

    def add_error(label, messages)
      @errors << { label: label, messages: Array(messages) }
    end

    def nothing_to_update?
      updated_count.zero? && errors.empty?
    end
  end

  def self.normalize_step_type(description)
    description.to_s.strip
  end

  def self.group_label(step_number, step_type_description)
    type = step_type_description.to_s.strip
    type = I18n.t('school_calendar_posting_dates.default_step_type') if type.blank?

    "#{step_number}º #{type}"
  end

  def initialize(year:)
    @year = year
  end

  def groups
    grouped = Hash.new { |hash, key| hash[key] = { school: [], classroom: [] } }

    school_steps.each do |step|
      grouped[group_key(step.step_number, step.school_calendar.step_type_description)][:school] << step
    end

    classroom_steps.each do |step|
      grouped[group_key(step.step_number, step.school_calendar_classroom.step_type_description)][:classroom] << step
    end

    grouped.keys.sort_by { |step_number, type|
      [ActiveSupport::Inflector.transliterate(type.to_s).downcase, step_number.to_i]
    }.map do |key|
      school = grouped[key][:school]
      classroom = grouped[key][:classroom]

      Group.new(
        key[0],
        key[1],
        school.map { |step| step.school_calendar.unity_id }.uniq.size,
        classroom.size,
        (school + classroom).map(&:start_date_for_posting),
        (school + classroom).map(&:end_date_for_posting)
      )
    end
  end

  def apply(groups:, apply_to_classroom_steps: true)
    result = Result.new

    Array(groups).each do |group_attrs|
      apply_group(
        group_attrs,
        apply_to_classroom_steps: apply_to_classroom_steps,
        result: result
      )
    end

    result
  end

  private

  attr_reader :year

  def apply_group(group_attrs, apply_to_classroom_steps:, result:)
    attrs = group_attrs.respond_to?(:to_unsafe_h) ? group_attrs.to_unsafe_h : group_attrs
    attrs = attrs.with_indifferent_access

    start_raw = attrs[:start_date_for_posting]
    end_raw = attrs[:end_date_for_posting]
    return if start_raw.blank? && end_raw.blank?

    label = self.class.group_label(attrs[:step_number], attrs[:step_type_description])
    start_date = parse_date(start_raw)
    end_date = parse_date(end_raw)

    if start_raw.present? && start_date.nil?
      result.add_error(label, I18n.t('school_calendar_posting_dates.errors.invalid_start_date'))
      return
    end

    if end_raw.present? && end_date.nil?
      result.add_error(label, I18n.t('school_calendar_posting_dates.errors.invalid_end_date'))
      return
    end

    update_collection(school_steps_for(attrs), start_date, end_date, result)

    return unless apply_to_classroom_steps

    update_collection(classroom_steps_for(attrs), start_date, end_date, result)
  end

  def update_collection(relation, start_date, end_date, result)
    relation.find_each do |step|
      begin
        step.start_date_for_posting = start_date if start_date.present?
        step.end_date_for_posting = end_date if end_date.present?
        next unless step.changed?

        step.save!
        result.add_updated
      rescue ActiveRecord::RecordInvalid
        result.add_error(step_error_label(step), step.errors.full_messages)
      end
    end
  end

  def school_steps
    SchoolCalendarStep
      .joins(:school_calendar)
      .includes(school_calendar: :unity)
      .where(school_calendars: { year: year })
  end

  def classroom_steps
    SchoolCalendarClassroomStep
      .joins(school_calendar_classroom: :school_calendar)
      .includes(school_calendar_classroom: [:school_calendar, :classroom])
      .where(school_calendars: { year: year })
  end

  def school_steps_for(attrs)
    school_steps
      .where(step_number: attrs[:step_number])
      .where('COALESCE(school_calendars.step_type_description, ?) = ?', '', normalized_type(attrs))
  end

  def classroom_steps_for(attrs)
    classroom_steps
      .where(step_number: attrs[:step_number])
      .where('COALESCE(school_calendar_classrooms.step_type_description, ?) = ?', '', normalized_type(attrs))
  end

  def group_key(step_number, step_type_description)
    [step_number.to_i, self.class.normalize_step_type(step_type_description)]
  end

  def normalized_type(attrs)
    self.class.normalize_step_type(attrs[:step_type_description])
  end

  def parse_date(value)
    return if value.blank?
    return value if value.is_a?(Date)

    string = value.to_s.strip
    return Date.strptime(string, '%d/%m/%Y') if string.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
    return Date.parse(string) if string.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    nil
  rescue ArgumentError
    nil
  end

  def step_error_label(step)
    if step.is_a?(SchoolCalendarClassroomStep)
      classroom = step.classroom
      unity_name = step.school_calendar.try(:unity).try(:name)
      "#{unity_name} — #{classroom} (#{step.school_term})"
    else
      "#{step.unity.name} (#{step.school_term})"
    end
  end
end
