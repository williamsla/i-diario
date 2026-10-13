class ConceptualExamValueDecorator
  include Decore
  include Decore::Proxy

  def data_for_select2
    rounding_table = rounding_table_for_value
    return [] if rounding_table.blank?

    elements = rounding_table.rounding_table_values.map { |rounding_table_value|
      {
        id: ConceptValueMatcher.canonical(rounding_table_value.value),
        name: rounding_table_value.to_s,
        text: rounding_table_value.to_s
      }
    }
    add_empty_element(elements)
  end

  def selected_option_id
    ConceptValueMatcher.option_id(rounding_table_for_value, value)
  end

  private

  def rounding_table_for_value
    return @rounding_table_for_value if defined?(@rounding_table_for_value)

    @rounding_table_for_value = lookup_rounding_table
  end

  def lookup_rounding_table
    return if conceptual_exam.blank? || conceptual_exam.student.blank? || conceptual_exam.classroom.blank?

    classroom_grade = ClassroomsGrade.by_student_id(conceptual_exam.student.id)
                                     .by_classroom_id(conceptual_exam.classroom.id)
                                     &.first
    return if classroom_grade.blank?

    exam_rule = classroom_grade.exam_rule
    return if exam_rule.blank?

    if conceptual_exam.student.try(:uses_differentiated_exam_rule)
      exam_rule = exam_rule.differentiated_exam_rule || exam_rule
    end

    exam_rule&.conceptual_rounding_table
  end

  def add_empty_element(elements)
    empty_element = { id: "empty", name: "<option></option>", text: "" }
    elements.insert(0, empty_element)
    elements.to_json
  end
end
