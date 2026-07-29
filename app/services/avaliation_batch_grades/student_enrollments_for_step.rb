# frozen_string_literal: true

module AvaliationBatchGrades
  # Alunos da turma/disciplina na etapa, incluindo inativos (transferido, fora do período).
  # "Ativo" = enturmado na data de referência (último dia da etapa).
  # Pode liberar nota = inativo na data de referência, mas com overlap na etapa.
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

    def batch_reference_date
      (step.end_at.presence || step.start_at).to_date
    end

    def student_active_in_step?(student_enrollment)
      enrollment_active_on_date?(student_enrollment, batch_reference_date)
    end

    def student_active_in_step_by_student_id?(student_id)
      StudentEnrollment
        .by_classroom(classroom)
        .by_discipline(discipline)
        .by_student(student_id)
        .by_date(batch_reference_date)
        .active
        .any?
    end

    def student_attended_step?(student_enrollment)
      StudentEnrollment
        .where(id: student_enrollment)
        .by_classroom(classroom)
        .by_discipline(discipline)
        .by_date_range(step.start_at, step.end_at)
        .active
        .any?
    end

    def student_attended_step_by_student_id?(student_id)
      StudentEnrollment
        .by_classroom(classroom)
        .by_discipline(discipline)
        .by_student(student_id)
        .by_date_range(step.start_at, step.end_at)
        .active
        .any?
    end

    def student_can_unlock_notes?(student_enrollment)
      !student_active_in_step?(student_enrollment) && student_attended_step?(student_enrollment)
    end

    def enrollment_active_on_date?(student_enrollment, date)
      StudentEnrollment
        .where(id: student_enrollment)
        .by_classroom(classroom)
        .by_discipline(discipline)
        .by_date(date)
        .active
        .any?
    end

    def batch_student_display_name(enrollment, _active = nil)
      enrollment.student.name
    end

    def batch_student_left_at(enrollment)
      classroom_id = classroom.is_a?(Classroom) ? classroom.id : classroom
      sec = StudentEnrollmentClassroom
        .by_classroom(classroom_id)
        .by_student_enrollment(enrollment.id)
        .ordered
        .last
      left_at = sec&.left_at
      return nil if left_at.blank?

      left_at.is_a?(String) ? Date.parse(left_at) : left_at.to_date
    rescue ArgumentError, TypeError
      nil
    end

    def batch_student_status_message(enrollment, active)
      return nil if active

      left_at = batch_student_left_at(enrollment)
      if left_at.present?
        I18n.t(
          'avaliations.batch.transferred_on',
          date: I18n.l(left_at, format: :default)
        )
      else
        I18n.t('avaliations.batch.inactive_student_status')
      end
    end
  end
end
