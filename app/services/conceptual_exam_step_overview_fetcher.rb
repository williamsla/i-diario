# frozen_string_literal: true

class ConceptualExamStepOverviewFetcher
  StudentRow = Struct.new(:student, :conceptual_exam, :status, :updated_at)
  StepOverview = Struct.new(:step, :complete, :incomplete, :pending, :total, :current) do
    def complete_percentage
      return 0 if total.to_i.zero?

      ((complete.to_f / total) * 100).round
    end
  end

  PENDING = 'pending'

  def initialize(classroom:, teacher_id:, discipline: nil, annual: false)
    @classroom = classroom
    @teacher_id = teacher_id
    @discipline = discipline
    @annual = annual
  end

  def overview_for_steps(steps, current_step_id: nil)
    Array(steps).map { |step| overview_for_step(step, current_step_id: current_step_id) }
  end

  def overview_for_step(step, current_step_id: nil)
    rows = student_rows_for_step(step)
    counts = count_statuses(rows)

    StepOverview.new(
      step,
      counts[:complete],
      counts[:incomplete],
      counts[:pending],
      counts[:total],
      current_step?(step, current_step_id)
    )
  end

  def student_rows_for_step(step, student_name: nil, status: nil)
    student_ids = enrolled_student_ids(step)
    return [] if student_ids.blank?

    exams_by_student = existing_exams_by_student(step, student_ids)
    incomplete_ids = incomplete_exam_ids(exams_by_student.values.map(&:id))

    students = Student.where(id: student_ids).ordered
    rows = students.map do |student|
      exam = exams_by_student[student.id]
      row_status = status_for(exam, incomplete_ids)

      StudentRow.new(student, exam, row_status, exam && exam.updated_at)
    end

    rows = filter_by_student_name(rows, student_name)
    filter_by_status(rows, status)
  end

  def counts_for_rows(rows)
    count_statuses(rows)
  end

  private

  attr_reader :classroom, :teacher_id, :discipline, :annual

  def enrolled_student_ids(step)
    start_at, end_at = enrollment_period(step)

    ConceptualExamStudentEnrollments.new(
      classroom: classroom,
      discipline: discipline,
      start_at: start_at,
      end_at: end_at
    ).student_enrollments.map(&:student_id).uniq
  end

  def enrollment_period(step)
    if annual
      steps = StepsFetcher.new(classroom).steps
      first_step = steps.first
      last_step = steps.last
      [
        (first_step && first_step.start_at) || step.start_at,
        (last_step && last_step.end_at) || step.end_at
      ]
    else
      [step.start_at, step.end_at]
    end
  end

  def existing_exams_by_student(step, student_ids)
    scope = ConceptualExam.by_classroom(classroom.id).where(student_id: student_ids)
    scope = scope.by_step_number(step.step_number) unless annual

    scope.includes(:conceptual_exam_values, :student)
         .order(:student_id, updated_at: :asc)
         .index_by(&:student_id)
  end

  def incomplete_exam_ids(exam_ids)
    return [] if exam_ids.blank?

    ConceptualExam.where(id: exam_ids)
                  .by_status(classroom.id, teacher_id, ConceptualExamStatus::INCOMPLETE)
                  .pluck(:id)
  end

  def status_for(exam, incomplete_ids)
    return PENDING if exam.blank?
    return ConceptualExamStatus::INCOMPLETE if incomplete_ids.include?(exam.id)

    ConceptualExamStatus::COMPLETE
  end

  def count_statuses(rows)
    {
      complete: rows.count { |row| row.status == ConceptualExamStatus::COMPLETE },
      incomplete: rows.count { |row| row.status == ConceptualExamStatus::INCOMPLETE },
      pending: rows.count { |row| row.status == PENDING },
      total: rows.size
    }
  end

  def filter_by_student_name(rows, student_name)
    return rows if student_name.blank?

    query = I18n.transliterate(student_name.to_s).downcase
    rows.select do |row|
      name = I18n.transliterate(row.student.name.to_s).downcase
      social = I18n.transliterate(row.student.social_name.to_s).downcase
      name.include?(query) || social.include?(query)
    end
  end

  def filter_by_status(rows, status)
    return rows if status.blank?

    rows.select { |row| row.status.to_s == status.to_s }
  end

  def current_step?(step, current_step_id)
    return false if annual || current_step_id.blank?

    step.id.to_s == current_step_id.to_s
  end
end
