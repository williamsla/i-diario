# frozen_string_literal: true

class AeeTeachingPlanDetail < ApplicationRecord
  include Audit

  audited associated_with: :teaching_plan

  belongs_to :teaching_plan, inverse_of: :aee_teaching_plan_detail, optional: true

  has_enumeration_for :attendance_composition, with: AeeAttendanceCompositions, create_helpers: true

  NESTED_ATTRIBUTES = [
    :id,
    :attendance_period,
    :attendance_frequency,
    :attendance_duration,
    :attendance_composition,
    :student_characteristics,
    :general_objectives,
    :cognitive_objectives,
    :psychomotor_objectives,
    :socioemotional_objectives,
    :activities,
    :resources,
    :regular_teacher_name,
    :specialized_teacher_name,
    :mediator_name,
    :pedagogical_coordinator_name,
    :school_management_name,
    :responsible_name,
    :document_date
  ].freeze

  validates_date :document_date, allow_blank: true

  def location_and_date
    unity = teaching_plan&.unity
    city = unity&.address&.city
    state = unity&.address&.state.to_s.upcase
    place = [city, state].reject(&:blank?).join('-')
    date_label = I18n.l(document_date, format: :long) if document_date.present?

    [place.presence, date_label].compact.join(', ')
  end
end
