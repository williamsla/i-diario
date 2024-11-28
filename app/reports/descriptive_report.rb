# require 'action_view'
require 'nokogiri'

class DescriptiveReport < BaseReport
  include ActionView::Helpers::NumberHelper

  def self.build(entity_configuration, unity, year, descriptives, students, classroom, is_annual=false, is_embedded=false)
    new.build(entity_configuration, unity, year, descriptives, students, classroom, is_annual, is_embedded)
  end

  def build(entity_configuration, unity, year, descriptives, students, classroom, is_annual=false, is_embedded=false)
    @entity_configuration = entity_configuration
    @year = year
    @descriptives = descriptives
    @students = students
    @unity = unity
    @classroom = classroom
    @show_subtitles = false
    @display_header_on_all_reports_pages = true
    @is_embedded = is_embedded
    @is_annual = is_annual

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

    header_table_data = [
                          [header_cell]
                        ]
    header_table_data << [logo_cell, entity_organ_and_unity_cell] if @is_embedded == false
    
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
    student_cell_header = make_cell(content: "Aluno", size: 10, borders: [:top, :left, :right], padding: [1, 2, 4, 4], colspan:2)
    student_cell = make_cell(content: student.name, size: 10, borders: [:bottom, :left, :right], padding: [1, 2, 4, 4], colspan:2)
    year_cell = make_cell(content: "Ano: #{@year}", size: 10, borders: [:top, :left, :right], padding: [1, 2, 4, 4], colspan:2)
    classroom_cell = make_cell(content: "Turma: #{@classroom.description}", size: 10, borders: [:bottom, :left, :right], padding: [1, 2, 4, 4], colspan:2)

    identification_table_data = [
      [student_cell_header, year_cell],
      [student_cell, classroom_cell]
    ]

    table(identification_table_data, width: bounds.width) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def write_descriptive_exam(exam_number, exam_value)

    descriptive_number = @is_annual == true ? '' : exam_number
    exam_cell_header = make_cell(content: "Parecer #{descriptive_number}", size: 8, font_style: :bold, width: 100, borders: [:left, :right], padding: [2, 2, 4, 4], colspan: 2)
    exam_cell = make_cell(content: Nokogiri::HTML(exam_value.value).text, size: 10, width: 100, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 2)
    
    identification_table_data = [
      [exam_cell_header],
      [exam_cell]      
    ]

    table(identification_table_data, width: bounds.width) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    # move_down GAP
  end

  def body
    page_content do
      @students.each_with_index do |student, index|
        identification(student)
        
        descriptives_by_student = @descriptives.select{ |item| item.student.id == student.id}
        if descriptives_by_student.empty?
          move_down 50
        else
          descriptives_by_student.each_with_index do |exam, index|
            write_descriptive_exam(index+1, exam)
          end
        end

        move_down 50
        text('___________________________________________', size: 8, align: :center)
        text('Professor(a)', size: 10, align: :center)
        
        start_new_page
      end

      
    end
  end

  def footer
    
    page_footer(draw_datetime: true) do
      # repeat(:all) do
        # draw_text('Legendas: N - Não enturmado, D - Dispensado da avaliação ou disciplina', size: 8, at: [0, 15]) if @show_subtitles
        
      # end
    end

  end

end
