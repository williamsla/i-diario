# frozen_string_literal: true

# Enturmação usada no parecer da turma.
# Quem saiu e voltou para a mesma turma usa a enturmação vigente.
# A data de saída do remanejamento anterior não bloqueia o campo.
class DescriptiveExamStudentEnrollment
  def self.choose(enrollments, period_start:, period_end:)
    new(enrollments, period_start, period_end).choose
  end

  def self.blocked?(enrollment, period_start:)
    return false if enrollment.blank?

    left_at = parse_date(enrollment.left_at)
    start_at = parse_date(period_start)
    start_at.present? && left_at.present? && left_at < start_at
  end

  def self.parse_date(value)
    return if value.blank?

    value.to_date
  rescue ArgumentError, TypeError
    nil
  end

  def initialize(enrollments, period_start, period_end)
    @enrollments = Array(enrollments).compact
    @period_start = self.class.parse_date(period_start)
    @period_end = self.class.parse_date(period_end)
  end

  def choose
    return if enrollments.blank?

    pool = covering.presence || enrollments
    pool.max_by { |enrollment| sort_key(enrollment) }
  end

  private

  attr_reader :enrollments, :period_start, :period_end

  def covering
    enrollments.select { |enrollment| covers?(enrollment) }
  end

  def covers?(enrollment)
    joined_at = self.class.parse_date(enrollment.joined_at)
    left_at = self.class.parse_date(enrollment.left_at)
    return false if joined_at.blank?
    return false if period_end.present? && joined_at > period_end
    return false if left_at.present? && left_at == joined_at
    return true if left_at.blank?
    return true if period_start.blank?

    left_at >= period_start
  end

  def sort_key(enrollment)
    left_at = self.class.parse_date(enrollment.left_at)
    joined_at = self.class.parse_date(enrollment.joined_at) || Date.new(1, 1, 1)

    [
      left_at.blank? ? 1 : 0,
      left_at || Date.new(1, 1, 1),
      joined_at,
      enrollment.id.to_i
    ]
  end
end
