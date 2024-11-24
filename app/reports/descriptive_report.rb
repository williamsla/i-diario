require 'action_view'

class DescriptiveReport < BaseReport
  include ActionView::Helpers::NumberHelper

  def self.build(entity_configuration, year, school_calendar_step, students, unity, classroom, test_setting)
    new.build(entity_configuration, year, school_calendar_step, students, unity, classroom, test_setting)
  end

  def build(entity_configuration, year, school_calendar_step, students, unity, classroom, test_setting)
    @entity_configuration = entity_configuration
    @year = year
    @school_calendar_step = school_calendar_step
    @students = students
    @unity = unity
    @classroom = classroom
    @test_setting = test_setting
    @show_subtitles = false
    @display_header_on_all_reports_pages = true

    header
    body
    footer

    self
  end

  private

  def header
    header_cell = make_cell(content: 'Parecer descritivo', size: 12, font_style: :bold, background_color: 'DEDEDE', height: 20, padding: [2, 2, 4, 4], align: :center, colspan: 2)
    begin
      logo_cell = make_cell(image: open(@entity_configuration.logo.url), fit: [50, 50], width: 70, rowspan: 4, position: :center, vposition: :center)
    rescue
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''

    entity_organ_and_unity_cell = make_cell(content: "#{entity_name}\n#{organ_name}\n#{@unity.name}", size: 12, leading: 1.5, align: :center, valign: :center, rowspan: 4, padding: [6, 0, 8, 0])

    header_table_data = [[header_cell],
                        [logo_cell, entity_organ_and_unity_cell]
                      ]

    page_header do
      table(header_table_data, width: bounds.width) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def identification(student)
    header_cell = make_cell(content: 'Identificação', size: 12, font_style: :bold, background_color: 'DEDEDE', height: 20, padding: [2, 2, 4, 4], align: :center, colspan: 2)

    unity_cell_header = make_cell(content: 'Unidade', size: 8, font_style: :bold, width: 100, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 2)
    student_cell_header = make_cell(content: 'Aluno', size: 8, font_style: :bold, width: 100, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    classroom_cell_header = make_cell(content: 'Turma', size: 8, font_style: :bold, width: 100, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    year_cell_header = make_cell(content: 'Ano letivo', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    step_cell_header = make_cell(content: 'Etapa', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4])

    unity_cell = make_cell(content: @unity.name, size: 10, width: 100, borders: [:left, :right], padding: [0, 2, 4, 4], colspan: 2)
    student_cell = make_cell(content: student.name, size: 10, borders: [:left, :right], padding: [0, 2, 4, 4])
    classroom_cell = make_cell(content: @classroom.description, size: 10, borders: [:left, :right], padding: [0, 2, 4, 4])
    year_cell = make_cell(content: @year.to_s, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])
    step_cell = make_cell(content: @school_calendar_step.to_s, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])

    identification_table_data = [
      [header_cell],
      [unity_cell_header],
      [unity_cell],
      [student_cell_header, classroom_cell_header],
      [student_cell, classroom_cell],
      [year_cell_header, step_cell_header],
      [year_cell, step_cell]
    ]

    table(identification_table_data, width: bounds.width) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def disciplines_table(student)
    disciplines = {}
    subheader_cells = []

    table([[header_cell]], row_colors: ['DEDEDE'], width: bounds.width) do |t|
      t.cells.border_width = 0.25
      t.before_rendering_page do |page|
        page.row(0).border_top_width = 0.25
        page.row(-1).border_bottom_width = 0.25
        page.column(0).border_left_width = 0.25
        page.column(-1).border_right_width = 0.25
      end
    end

    table(data, row_colors: ['FFFFFF', 'DEDEDE'], width: bounds.width) do |t|
      t.cells.border_width = 0.25
      t.before_rendering_page do |page|
        page.row(0).border_top_width = 0.25
        page.row(-1).border_bottom_width = 0.25
        page.column(0).border_left_width = 0.25
        page.column(-1).border_right_width = 0.25
      end
    end

    move_down 50
    text('____________________________', size: 8, align: :center)
    text('Secretário(a) escolar', size: 10, align: :center)
  end

  def body
    page_content do
      @students.each_with_index do |student, index|
        identification(student)
        # disciplines_table(student)

        start_new_page if index != @students.size - 1
      end
    end
  end

  def footer
    page_footer(draw_datetime: true) do
      repeat(:all) do
        draw_text('Legendas: N - Não enturmado, D - Dispensado da avaliação ou disciplina', size: 8, at: [0, 15]) if @show_subtitles
      end
    end
  end

end
