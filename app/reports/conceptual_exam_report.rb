# frozen_string_literal: true

class ConceptualExamReport < BaseReport
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
      colspan: @disciplines.size + 1
    )
    begin
      logo_cell = make_cell(image: open(@entity_configuration.logo.url), fit: [50, 50], width: 70, rowspan: 3, position: :center, vposition: :center)
    rescue
      logo_cell = make_cell(content: '', width: 70, rowspan: 3)
    end

    entity_name = @entity_configuration&.entity_name || ''
    organ_name = @entity_configuration&.organ_name || ''
    entity_organ_unity = make_cell(
      content: "#{entity_name}\n#{organ_name}\n#{@unity.name}",
      size: 10,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 3,
      padding: [4, 2, 8, 2]
    )

    step_cell = make_cell(
      content: "#{ConceptualExam.human_attribute_name(:classroom)}: #{@classroom.description} | #{ConceptualExam.human_attribute_name(:step)}: #{@step.to_s}",
      size: 10,
      colspan: [@disciplines.size, 1].max,
      padding: [2, 2, 4, 4]
    )

    header_data = [[title], [logo_cell, entity_organ_unity, step_cell]]

    page_header do
      table(header_data, width: bounds.width) do
        cells.border_width = 0.25
      end
      move_down 8
    end
  end

  def body
    page_content do
      return if @students.blank?

      num_cols = [@disciplines.size, 1].max
      col_widths = [bounds.width * 0.35] + Array.new(@disciplines.size) { (bounds.width * 0.65) / num_cols }

      # Cabeçalho da tabela: Aluno | Disciplina 1 | Disciplina 2 | ...
      header_cells = [
        make_cell(content: Student.human_attribute_name(:name), size: 8, font_style: :bold, background_color: 'E8E8E8', padding: [4, 2])
      ]
      @disciplines.each do |d|
        header_cells << make_cell(content: d.description.to_s.truncate(20), size: 7, font_style: :bold, background_color: 'E8E8E8', padding: [4, 2])
      end
      table_data = [header_cells]

      @students.each do |student|
        conceptual_exam = @conceptual_exams_by_student[student.id]
        values_by_discipline = conceptual_exam ? conceptual_exam.conceptual_exam_values.index_by(&:discipline_id) : {}

        row_cells = [
          make_cell(content: student.name.to_s.truncate(35), size: 8, padding: [3, 2])
        ]
        @disciplines.each do |discipline|
          value_record = values_by_discipline[discipline.id]
          raw_value = value_record&.value
          cell_content = concept_display_name(@classroom, student, raw_value)
          row_cells << make_cell(content: cell_content.to_s, size: 8, padding: [3, 2])
        end
        table_data << row_cells
      end

      table(table_data, width: bounds.width, column_widths: col_widths, cell_style: { border_width: 0.25 }) do
        row(0).font_style = :bold
      end
    end
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
