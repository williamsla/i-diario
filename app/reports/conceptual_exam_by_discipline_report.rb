# frozen_string_literal: true

# Uma página (ou mais, se a turma não couber) por disciplina.
# Cada aluno aparece com o conceito recebido em cada etapa.
class ConceptualExamByDisciplineReport < BaseReport
  STUDENTS_PER_PAGE = 24

  def self.build(entity_configuration, unity, classroom, columns, disciplines, students_by_discipline_id, concepts)
    new.build(entity_configuration, unity, classroom, columns, disciplines, students_by_discipline_id, concepts)
  end

  def build(entity_configuration, unity, classroom, columns, disciplines, students_by_discipline_id, concepts)
    @entity_configuration = entity_configuration
    @unity = unity
    @classroom = classroom
    @columns = columns
    @disciplines = disciplines
    @students_by_discipline_id = students_by_discipline_id || {}
    @concepts = concepts || {}

    header
    body
    footer

    self
  end

  private

  def header
    title = make_cell(
      content: 'Avaliações conceituais',
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
      content: "#{ConceptualExam.human_attribute_name(:classroom)}: #{@classroom.description}",
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
    first_section = true

    @disciplines.each do |discipline|
      students = Array(@students_by_discipline_id[discipline.id])
      next if students.blank?

      students.each_slice(STUDENTS_PER_PAGE).with_index do |slice, slice_index|
        start_new_content_page unless first_section
        first_section = false

        page_content do
          discipline_heading(discipline)
          students_table(discipline, slice, slice_index * STUDENTS_PER_PAGE)
        end
      end
    end
  end

  def discipline_heading(discipline)
    table(
      [[
        make_cell(
          content: "#{ConceptualExamValue.human_attribute_name(:discipline)}: #{discipline.description}",
          size: 10,
          font_style: :bold,
          background_color: 'DEDEDE',
          padding: [4, 4]
        )
      ]],
      width: bounds.width,
      cell_style: { border_width: 0.25 }
    )
    move_down 4
  end

  def students_table(discipline, students, sequence_offset)
    column_count = [@columns.size, 1].max
    sequence_width = 22
    name_width = bounds.width * 0.42
    step_width = (bounds.width - sequence_width - name_width) / column_count
    column_widths = [sequence_width, name_width] + Array.new(column_count, step_width)

    header_cells = [
      make_cell(content: 'Nº', size: 8, font_style: :bold, background_color: 'E8E8E8', align: :center, padding: [4, 2]),
      make_cell(content: Student.human_attribute_name(:name), size: 8, font_style: :bold, background_color: 'E8E8E8', padding: [4, 2])
    ]
    @columns.each do |column|
      header_cells << make_cell(
        content: column[:label].to_s,
        size: 7,
        font_style: :bold,
        background_color: 'E8E8E8',
        align: :center,
        padding: [4, 2]
      )
    end

    table_data = [header_cells]
    students.each_with_index do |student, index|
      table_data << student_row(discipline, student, sequence_offset + index + 1)
    end

    table(table_data, width: bounds.width, column_widths: column_widths, cell_style: { border_width: 0.25, size: 8 }) do
      row(0).font_style = :bold
    end
  end

  def student_row(discipline, student, sequence)
    cells = [
      make_cell(content: sequence.to_s, size: 8, align: :center, padding: [3, 2]),
      make_cell(content: student.name.to_s, size: 8, padding: [3, 2])
    ]

    @columns.each do |column|
      raw_value = @concepts[[student.id, discipline.id, column[:key]]]
      cells << make_cell(
        content: concept_display_name(student, raw_value),
        size: 8,
        align: :center,
        padding: [3, 2]
      )
    end

    cells
  end

  def concept_display_name(student, value)
    return '-' if value.blank?

    exam_rule = ExamRuleFetcher.fetch(@classroom, student)
    ConceptValueMatcher.display(exam_rule&.conceptual_rounding_table, value).presence || '-'
  end

  def footer
    page_footer(draw_datetime: true)
  end
end
