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
        ConceptValueMatcher.canonical(rtv.value),
        { title: rtv.to_s }
      ]
    }
  end

  def concept_option_short_label(rounding_table_value)
    rounding_table_value.label.to_s.strip.presence || rounding_table_value.to_s
  end

  # Normaliza decimal/BigDecimal para o value do <option>.
  # BigDecimal#to_s varia com a escala ("0.1e2", "10.0", "10.00") e o select fica em branco.
  def concept_option_value(value)
    ConceptValueMatcher.canonical(value)
  end

  # Id da opção que representa o conceito já lançado, mesmo se a escala do decimal diferir.
  def concept_selected_option(classroom, student, value)
    return if value.nil?

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    ConceptValueMatcher.option_id(exam_rule&.conceptual_rounding_table, value)
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
