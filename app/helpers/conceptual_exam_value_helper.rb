module ConceptualExamValueHelper
  # Retorna opções para select de conceito (value) conforme regra do aluno na turma.
  # Usado no layout em lote (form_batch) onde cada célula aluno x disciplina precisa do dropdown correto.
  def concept_options_for_student(classroom, student)
    return [] if classroom.blank? || student.blank?

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    rounding_table = exam_rule&.conceptual_rounding_table
    return [] if rounding_table.blank?

    rounding_table.rounding_table_values.map { |rtv| [rtv.to_s, concept_option_value(rtv.value)] }
  end

  # Normaliza decimal/BigDecimal para o value do <option>, evitando mismatch na reexibição
  # (ex.: BigDecimal#to_s => "0.1e2" vs "10.0" enviado pelo formulário).
  def concept_option_value(value)
    return if value.nil?

    value.to_d.to_s('F')
  rescue ArgumentError, TypeError, NoMethodError
    value.to_s
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
