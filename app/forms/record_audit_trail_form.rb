# frozen_string_literal: true

class RecordAuditTrailForm
  include ActiveModel::Model

  RECORD_TYPES = %w[frequency content avaliation grades teaching_plan lesson_plan opinion].freeze
  DEFAULT_RECORD_TYPES = %w[frequency content].freeze

  attr_accessor :unity_id,
                :classroom_id,
                :teacher_id,
                :discipline_id,
                :start_at,
                :end_at,
                :school_calendar_year,
                :record_types

  validates :start_at, presence: true, date: true, timeliness: {
    on_or_before: :end_at, type: :date, on_or_before_message: I18n.t('errors.messages.on_or_before_message')
  }
  validates :end_at, presence: true, date: true, timeliness: {
    on_or_after: :start_at, type: :date, on_or_after_message: I18n.t('errors.messages.on_or_after_message')
  }
  validates :unity_id, presence: true
  validates :school_calendar_year, presence: true

  def selected_record_types
    types = Array(record_types).reject(&:blank?)
    types = DEFAULT_RECORD_TYPES if types.empty?

    types & RECORD_TYPES
  end

  def unity
    Unity.find_by(id: unity_id)
  end

  def classroom
    return if classroom_id.blank?

    @classroom ||= Classroom.includes(grades: :course).find_by(id: classroom_id)
  end

  def discipline_filter_label
    self.class.filter_label_for(classroom)
  end

  def discipline_filter_value
    discipline = Discipline.includes(:knowledge_area).find_by(id: discipline_id)
    return I18n.t('reports.record_audit_trail_report.all') if discipline.blank?

    self.class.discipline_display_name(discipline, classroom)
  end

  def self.filter_label_for(classroom)
    key = classroom&.early_childhood_or_aee? ? 'knowledge_area' : 'discipline'
    I18n.t("record_audit_trails.form.#{key}")
  end

  def self.discipline_options(disciplines, classroom, selected_id = nil)
    records = Array(disciplines&.to_a).compact
    records = unique_by_knowledge_area(records, selected_id) if classroom&.early_childhood_or_aee?

    records.map { |discipline| discipline_option(discipline, classroom) }
           .sort_by { |option| option.name.to_s }
  end

  def self.discipline_display_name(discipline, classroom)
    if classroom&.early_childhood_or_aee?
      discipline.knowledge_area&.to_s.presence || discipline.to_s
    else
      discipline.to_s
    end
  end

  def self.discipline_option(discipline, classroom)
    name = discipline_display_name(discipline, classroom)
    RecordAuditTrailTeacherLinks::Option.new(discipline.id, name, name)
  end

  def self.unique_by_knowledge_area(disciplines, selected_id)
    disciplines.group_by { |discipline| discipline.knowledge_area_id || "discipline-#{discipline.id}" }
               .values
               .map { |group| preferred_discipline(group, selected_id) }
  end

  def self.preferred_discipline(group, selected_id)
    group.find { |discipline| discipline.id.to_s == selected_id.to_s } ||
      group.find(&:grouper?) ||
      group.first
  end

  private_class_method :discipline_option, :unique_by_knowledge_area, :preferred_discipline
end
