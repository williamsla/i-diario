# Com a configuração geral ativa:
# - Calendário com 4 etapas: 2 opções de parecer (1º e 2º semestre), âncora no 2º e 4º bimestre
#   para o envio ao i-educar (pareceres-por-etapa).
# - Calendário com 2 etapas: 1 opção (semestre único), âncora na 2ª etapa.
# - Educação infantil com 2 etapas: 1 parecer por etapa (não agrupa).
class DescriptiveExamSemesterCalendar
  STEP_COUNTS_FOR_GROUPING = [2, 4].freeze
  INFANTIL_GRADE_PATTERN = /creche|pre|pre i|pre ii|pre[- ]escola(r)?|maternal|bercario|jardim|infantil|aee/
  INFANTIL_COURSE_PATTERN = /infantil|aee/

  class << self
    def enabled?(classroom)
      return false if classroom.blank?
      return false unless GeneralConfiguration.current.descriptive_exams_semester_calendar_steps

      steps_size = ordered_steps(classroom).size
      return false unless STEP_COUNTS_FOR_GROUPING.include?(steps_size)
      return false if steps_size == 2 && infantil_classroom?(classroom)

      true
    end

    def step_select_options(classroom)
      steps = ordered_steps(classroom)
      return [] if steps.blank?

      unless enabled?(classroom)
        return steps.map { |s| { id: s.id, description: s.to_s } }
      end

      case steps.size
      when 4
        steps.each_slice(2).map.with_index(1) do |pair, semester_index|
          anchor = pair.last
          {
            id: anchor.id,
            description: I18n.t(
              'descriptive_exams.semester_step_option',
              semester: semester_index,
              first_step: pair.first.step_number,
              last_step: pair.last.step_number
            )
          }
        end
      when 2
        anchor = steps.last
        [
          {
            id: anchor.id,
            description: I18n.t(
              'descriptive_exams.single_semester_step_option',
              first_step: steps.first.step_number,
              last_step: steps.last.step_number
            )
          }
        ]
      else
        steps.map { |s| { id: s.id, description: s.to_s } }
      end
    end

    def semester_pair_containing(classroom, anchor_step_number)
      return nil unless enabled?(classroom)
      return nil if anchor_step_number.blank?

      steps = ordered_steps(classroom)
      case steps.size
      when 4
        steps.each_slice(2) do |slice|
          numbers = slice.map(&:step_number)
          return slice if numbers.include?(anchor_step_number.to_i)
        end
        nil
      when 2
        return steps if steps.map(&:step_number).include?(anchor_step_number.to_i)

        nil
      else
        nil
      end
    end

    def ordered_steps(classroom)
      StepsFetcher.new(classroom).steps.to_a.sort_by(&:step_number)
    end

    private

    def infantil_classroom?(classroom)
      classroom.grades.any? do |grade|
        infantil_course_description?(grade.course&.description) ||
          infantil_grade_description?(grade.description)
      end
    end

    def infantil_grade_description?(description)
      return false if description.blank?

      I18n.transliterate(description.to_s.downcase).match?(INFANTIL_GRADE_PATTERN)
    end

    def infantil_course_description?(description)
      return false if description.blank?

      I18n.transliterate(description.to_s.downcase).match?(INFANTIL_COURSE_PATTERN)
    end
  end
end
