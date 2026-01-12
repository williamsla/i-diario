class DailyNoteStudentPresenter < BasePresenter
  def student_name_class
    name_class = 'multiline '

    if in_active_search
      name_class += 'in-active-search'
    elsif !active
      name_class += 'inactive-student'
    elsif exempted
      name_class += 'exempted-student'
    elsif dependence
      name_class += 'dependence-student'
    elsif exempted_from_discipline
      name_class += 'exempted-student-from-discipline'
    end

    name_class
  end

  def student_name
    if in_active_search
      "*****#{student}"
    elsif !active
      left_at_text = ""
      if left_at.present? && left_at.to_s.strip.present?
        begin
          left_at_date = left_at.is_a?(String) ? Date.parse(left_at) : left_at.to_date
          left_at_text = "\nSaiu em: #{I18n.l(left_at_date, format: :default)}"
        rescue
          # Se não conseguir fazer parse, não exibe a data
        end
      end
      "***#{student}#{left_at_text}"
    elsif exempted
      "**#{student}"
    elsif dependence
      dependence_text = "\nAluno(a) com matrícula de dependência nesta disciplina"
      "*#{student}#{dependence_text}"
    elsif exempted_from_discipline
      "****#{student}"
    else
      "#{student.to_s} #{grade_description}"
    end
  end

  def number_of_decimal_places
    daily_note.avaliation
              .test_setting
              .number_of_decimal_places
  end
end
