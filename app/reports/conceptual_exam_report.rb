# frozen_string_literal: true

class ConceptualExamReport < BaseReport
  # Acima deste limite as colunas ficam estreitas demais no layout horizontal
  HORIZONTAL_LAYOUT_MAX_DISCIPLINES = 8

  def self.build(entity_configuration, unity, classroom, step, students, disciplines, conceptual_exams_by_student)
    new.build(entity_configuration, unity, classroom, step, students, disciplines, conceptual_exams_by_student)
  end

  def build(entity_configuration, unity, classroom, step, students, disciplines, conceptual_exams_by_student)
    @entity_configuration = entity_configuration
    @unity = unity
    @classroom = classroom
    @step = step
    @students = students
    @disciplines = disciplines
    @conceptual_exams_by_student = conceptual_exams_by_student || {}

    header
    body
    footer

    self
  end

  private

  def header
    title = make_cell(
      content: I18n.t('conceptual_exam_report.pdf_title'),
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 3
    )
    begin
      logo_cell = make_cell(image: entity_logo_io, fit: [50, 50], width: 70, position: :center, vposition: :center)
    rescue
      logo_cell = make_cell(content: '', width: 70)
    end

    entity_name = @entity_configuration&.entity_name || ''
    organ_name = @entity_configuration&.organ_name || ''
    entity_organ_unity = make_cell(
      content: "#{entity_name}\n#{organ_name}\n#{@unity.name}",
      size: 10,
      leading: 1.5,
      align: :center,
      valign: :center,
      padding: [4, 2, 8, 2]
    )

    info_cell = make_cell(
      content: "#{ConceptualExam.human_attribute_name(:classroom)}: #{@classroom.description}\n#{ConceptualExam.human_attribute_name(:step)}: #{@step}",
      size: 10,
      leading: 1.5,
      valign: :center,
      padding: [4, 4, 4, 4]
    )

    header_data = [[title], [logo_cell, entity_organ_unity, info_cell]]

    page_header do
      table(header_data, width: bounds.width, column_widths: [70, bounds.width * 0.45, bounds.width * 0.55 - 70]) do
        cells.border_width = 0.25
      end
      move_down 8
    end
  end

  def body
    page_content do
      return if @students.blank?

      if vertical_layout?
        render_vertical_body
      else
        render_horizontal_body
      end
    end
  end

  def vertical_layout?
    @disciplines.size > HORIZONTAL_LAYOUT_MAX_DISCIPLINES
  end

  def render_horizontal_body
    num_cols = [@disciplines.size, 1].max
    col_widths = [bounds.width * 0.35] + Array.new(@disciplines.size) { (bounds.width * 0.65) / num_cols }

    header_cells = [
      make_cell(content: Student.human_attribute_name(:name), size: 8, font_style: :bold, background_color: 'E8E8E8', padding: [4, 2])
    ]
    @disciplines.each do |d|
      header_cells << make_cell(content: d.description.to_s.truncate(20), size: 7, font_style: :bold, background_color: 'E8E8E8', padding: [4, 2])
    end
    table_data = [header_cells]

    @students.each do |student|
      table_data << horizontal_student_row(student)
    end

    table(table_data, width: bounds.width, column_widths: col_widths, cell_style: { border_width: 0.25 }) do
      row(0).font_style = :bold
    end
  end

  def horizontal_student_row(student)
    values_by_discipline = values_by_discipline_for(student)

    row_cells = [
      make_cell(content: student.name.to_s.truncate(35), size: 8, padding: [3, 2])
    ]
    @disciplines.each do |discipline|
      raw_value = values_by_discipline[discipline.id]&.value
      cell_content = concept_display_name(@classroom, student, raw_value)
      row_cells << make_cell(content: cell_content.to_s, size: 8, padding: [3, 2])
    end
    row_cells
  end

  def render_vertical_body
    col_widths = [bounds.width * 0.75, bounds.width * 0.25]
    discipline_label = ConceptualExamValue.human_attribute_name(:discipline)
    value_label = ConceptualExamValue.human_attribute_name(:value)

    @students.each_with_index do |student, index|
      start_new_page if index.positive?

      student_header_table = [[
        make_cell(
          content: "#{Student.human_attribute_name(:name)}: #{student.name}",
          size: 9,
          font_style: :bold,
          background_color: 'DEDEDE',
          padding: [4, 4]
        )
      ]]
      table(student_header_table, width: bounds.width, cell_style: { border_width: 0.25 })

      column_headers = [
        make_cell(content: discipline_label, size: 8, font_style: :bold, background_color: 'E8E8E8', padding: [3, 2]),
        make_cell(content: value_label, size: 8, font_style: :bold, background_color: 'E8E8E8', padding: [3, 2], align: :center)
      ]

      table_data = [column_headers]
      values_by_discipline = values_by_discipline_for(student)

      @disciplines.each do |discipline|
        raw_value = values_by_discipline[discipline.id]&.value
        cell_content = concept_display_name(@classroom, student, raw_value)

        table_data << [
          make_cell(content: discipline.description.to_s, size: 8, padding: [3, 2]),
          make_cell(content: cell_content.to_s, size: 8, padding: [3, 2], align: :center)
        ]
      end

      table(table_data, width: bounds.width, column_widths: col_widths, header: true, cell_style: { border_width: 0.25 })
      move_down 10
    end
  end

  def values_by_discipline_for(student)
    conceptual_exam = @conceptual_exams_by_student[student.id]
    return {} unless conceptual_exam

    conceptual_exam.conceptual_exam_values.index_by(&:discipline_id)
  end

  def footer
    page_footer(draw_datetime: true)
  end

  def concept_display_name(classroom, student, value)
    return '-' if value.blank?

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    rounding_table = exam_rule&.conceptual_rounding_table
    return value.to_s if rounding_table.blank?

    rtv = rounding_table.rounding_table_values.find { |v| v.value.to_s == value.to_s }
    rtv ? rtv.label.to_s : value.to_s
  end
end
