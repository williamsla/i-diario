# frozen_string_literal: true

# Alunos da avaliação conceitual na turma/período.
# Remanejado no primeiro dia de aula não entra na turma antiga em nenhuma etapa.
class ConceptualExamStudentEnrollments
  def initialize(classroom:, discipline:, start_at:, end_at:, period: nil)
    @classroom = classroom
    @discipline = discipline
    @start_at = start_at
    @end_at = end_at
    @period = period
  end

  def student_enrollments
    enrollments = StudentEnrollmentsList.new(
      classroom: classroom,
      discipline: discipline,
      start_at: start_at,
      end_at: end_at,
      score_type: StudentEnrollmentScoreTypeFilters::CONCEPT,
      search_type: :by_date_range,
      period: period,
      show_inactive: false
    ).student_enrollments

    filter_present_in_classroom_period(enrollments)
  end

  private

  attr_reader :classroom, :discipline, :start_at, :end_at, :period

  def filter_present_in_classroom_period(enrollments)
    enrollment_ids = enrollments.map { |enrollment| enrollment.id if enrollment.respond_to?(:id) }.compact
    return enrollments if enrollment_ids.blank?

    secs_by_enrollment = StudentEnrollmentClassroom
      .where(student_enrollment_id: enrollment_ids)
      .includes(:classrooms_grade)
      .group_by(&:student_enrollment_id)

    valid_ids = enrollment_ids.select do |enrollment_id|
      secs = secs_by_enrollment[enrollment_id] || []
      secs.any? { |sec| in_classroom_period?(sec, secs) }
    end

    enrollments.select { |enrollment| valid_ids.include?(enrollment.id) }
  end

  def in_classroom_period?(sec, siblings)
    return false unless sec_classroom_id(sec) == classroom_id

    joined = parse_date(sec.joined_at)
    return false if joined.blank? || joined > end_date

    left = parse_date(sec.left_at) || inferred_left_at(sec, siblings)
    return true if left.blank?
    return false if joined == left
    return false if left <= first_class_day

    left > start_date
  end

  def inferred_left_at(sec, siblings)
    joined = parse_date(sec.joined_at)
    return if joined.blank?

    later_joins = siblings.map { |other|
      next if other.id == sec.id
      next if sec_classroom_id(other) == classroom_id

      other_joined = parse_date(other.joined_at)
      other_joined if other_joined && other_joined > joined
    }.compact

    later_joins.min
  end

  def first_class_day
    @first_class_day ||= begin
      classroom_record = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
      first_step = classroom_record && StepsFetcher.new(classroom_record).steps.first
      (first_step && first_step.start_at.to_date) || start_date
    end
  end

  def classroom_id
    @classroom_id ||= (classroom.is_a?(Classroom) ? classroom.id : classroom).to_i
  end

  def start_date
    @parsed_start_date ||= start_at.to_date
  end

  def end_date
    @parsed_end_date ||= end_at.to_date
  end

  def sec_classroom_id(sec)
    sec.classrooms_grade.try(:classroom_id)
  end

  def parse_date(value)
    return if value.blank?

    value.to_date
  rescue ArgumentError, TypeError
    nil
  end
end
