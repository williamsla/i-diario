module ConceptualExamValueHelper
  # Opções compactas para o lote: texto = sigla (label); title = descrição completa.
  def concept_options_for_student(classroom, student)
    return [] if classroom.blank? || student.blank?

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    rounding_table = exam_rule&.conceptual_rounding_table
    return [] if rounding_table.blank?

    rounding_table.rounding_table_values.map { |rtv|
      [
        concept_option_short_label(rtv),
        concept_option_value(rtv.value),
        { title: rtv.to_s }
      ]
    }
  end

  def concept_option_short_label(rounding_table_value)
    rounding_table_value.label.to_s.strip.presence || rounding_table_value.to_s
  end

  # Normaliza decimal/BigDecimal para o value do <option>, evitando mismatch na reexibição
  # (ex.: BigDecimal#to_s => "0.1e2" vs "10.0" enviado pelo formulário).
  def concept_option_value(value)
    return if value.nil?

    value.to_d.to_s('F')
  rescue ArgumentError, TypeError, NoMethodError
    value.to_s
  end

  def concept_legend_items_for_classroom(classroom, students)
    student = Array(students).find(&:present?)
    return [] if classroom.blank? || student.blank?

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    rounding_table = exam_rule&.conceptual_rounding_table
    return [] if rounding_table.blank?

    rounding_table.rounding_table_values.map { |rtv|
      [concept_option_short_label(rtv), rtv.to_s]
    }.uniq
  end

  def conceptual_exam_value_student_name_class(conceptual_exam_value)
    if conceptual_exam_value.exempted_discipline.to_s == 'true'
      'exempted-student-from-discipline'
    else
      ''
    end
  end

  def conceptual_exam_value_student_name(conceptual_exam_value)
    if conceptual_exam_value.exempted_discipline.to_s == 'true'
      "****#{conceptual_exam_value.discipline.description}"
    else
      conceptual_exam_value.discipline.description
    end
  end
end
