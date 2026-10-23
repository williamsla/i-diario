# frozen_string_literal: true

class AbsenceJustificationRelease
  def self.call(absence_justifications_student_id:, frequency_date:, class_number:)
    new(
      absence_justifications_student_id: absence_justifications_student_id,
      frequency_date: frequency_date,
      class_number: class_number
    ).call
  end

  def initialize(absence_justifications_student_id:, frequency_date:, class_number:)
    @absence_justifications_student_id = absence_justifications_student_id
    @frequency_date = frequency_date
    @class_number = class_number
  end

  def call
    return false if absence_justifications_student_id.blank?

    link = AbsenceJustificationsStudent.find_by(id: absence_justifications_student_id)
    justification = link&.absence_justification
    return false unless removable?(justification)

    destroyed = if justification.absence_justifications_students.count <= 1
                  justification.destroy
                else
                  link.destroy
                end

    destroyed.present?
  end

  private

  attr_reader :absence_justifications_student_id, :frequency_date, :class_number

  def removable?(justification)
    return false unless justification
    return false unless same_single_day?(justification)
    return false if covers_other_classes?(justification)
    return false if another_class?(justification)

    true
  end

  def same_single_day?(justification)
    return false if justification.absence_date.blank? || justification.absence_date_end.blank?

    start_date = justification.absence_date.to_date
    end_date = justification.absence_date_end.to_date

    start_date == end_date && start_date == frequency_date.to_date
  end

  def covers_other_classes?(justification)
    justification.class_number.nil? && specific_class?
  end

  def another_class?(justification)
    return false if justification.class_number.blank?

    justification.class_number.to_i != normalized_class_number
  end

  def specific_class?
    class_number.present? && class_number.to_i != 0
  end

  def normalized_class_number
    return 0 if class_number.blank?

    class_number.to_i
  end
end
