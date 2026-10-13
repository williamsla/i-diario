# frozen_string_literal: true

class AeePrefill
  class << self
    def paee_from_case_study(student:, classroom:, year:)
      case_study = find_case_study(student: student, classroom: classroom, year: year)
      return {} if case_study.blank?

      {
        student_characteristics: join_present(
          case_study.identification,
          case_study.potentialities_and_support
        ),
        methodology: case_study.accessibility_strategies
      }
    end

    def attendance_from_pei(student:, classroom:, year:)
      pei = find_pei(student: student, classroom: classroom, year: year)
      return {} if pei.blank?

      {
        aee_individual_plan_id: pei.id,
        session_objectives: pei.goals,
        pei_goals: pei.goals,
        pei_strategies: pei.strategies,
        pei_resources: pei.resources,
        duration: pei.linked_paee&.aee_teaching_plan_detail&.attendance_duration
      }
    end

    def content_record_from_pei(student:, classroom:, year:)
      pei = find_pei(student: student, classroom: classroom, year: year)
      return {} if pei.blank?

      {
        goals: pei.goals,
        strategies: pei.strategies,
        resources: pei.resources,
        characteristics: pei.characteristics,
        identified_difficulties: pei.identified_difficulties,
        contents: compact_texts(pei.strategies),
        objectives: compact_texts(pei.goals)
      }
    end

    def find_case_study(student:, classroom:, year:)
      return if student.blank? || classroom.blank? || year.blank?

      AeeCaseStudy.find_by(student_id: student.id, classroom_id: classroom.id, year: year)
    end

    def find_pei(student:, classroom:, year:)
      return if student.blank? || classroom.blank? || year.blank?

      AeeIndividualPlan.find_by(student_id: student.id, classroom_id: classroom.id, year: year)
    end

    def strip_html(value)
      ActionController::Base.helpers.strip_tags(value.to_s)
                            .gsub('&nbsp;', ' ')
                            .gsub(/[ \t]+/, ' ')
                            .gsub(/\n{3,}/, "\n\n")
                            .strip
                            .presence
    end

    private

    def join_present(*values)
      values.map { |value| strip_html(value) }.compact.join("\n\n").presence
    end

    def compact_texts(*values)
      values.map { |value| strip_html(value) }.compact
    end
  end
end
