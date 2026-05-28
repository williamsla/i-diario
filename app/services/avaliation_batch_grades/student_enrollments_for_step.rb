# frozen_string_literal: true

module AvaliationBatchGrades
  # Alunos da turma/disciplina na etapa, incluindo inativos (transferido, fora do período).
  module StudentEnrollmentsForStep
    extend ActiveSupport::Concern

    private

    def batch_student_enrollments
      StudentEnrollmentsList.new(
        classroom: classroom,
        discipline: discipline,
        start_at: step.start_at,
        end_at: step.end_at,
        score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
        search_type: :by_date_range
      ).student_enrollments
    end

    def student_active_in_step?(student_enrollment)
      StudentEnrollment
        .where(id: student_enrollment)
        .by_classroom(classroom)
        .by_discipline(discipline)
        .by_date_range(step.start_at, step.end_at)
        .active
        .any?
    end

    def student_active_in_step_by_student_id?(student_id)
      StudentEnrollment
        .by_classroom(classroom)
        .by_discipline(discipline)
        .by_student(student_id)
        .by_date_range(step.start_at, step.end_at)
        .active
        .any?
    end

    def batch_student_display_name(enrollment, active)
      student = enrollment.student
      return student.name if active

      left_at_text = batch_student_left_at_label(enrollment)
      "***#{student.name}#{left_at_text}"
    end

    def batch_student_left_at_label(enrollment)
      classroom_id = classroom.is_a?(Classroom) ? classroom.id : classroom
      sec = StudentEnrollmentClassroom
        .by_classroom(classroom_id)
        .by_student_enrollment(enrollment.id)
        .first
      left_at = sec&.left_at
      return '' if left_at.blank?

      left_at_date = left_at.is_a?(String) ? Date.parse(left_at) : left_at.to_date
      "\nSaiu em: #{I18n.l(left_at_date, format: :default)}"
    rescue ArgumentError, TypeError
      ''
    end
  end
end
