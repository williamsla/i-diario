# require 'action_view'
require 'nokogiri'

class DescriptiveReport < BaseReport
  include ActionView::Helpers::NumberHelper

  def self.build(entity_configuration, unity, year, descriptives_exams, descriptives_values, students, student_enrollment_classroom, classroom, is_annual=false, is_embedded=false)
    new.build(entity_configuration, unity, year, descriptives_exams, descriptives_values, students, student_enrollment_classroom, classroom, is_annual, is_embedded)
  end

  def build(entity_configuration, unity, year, descriptives_exams, descriptives_values, students, student_enrollment_classroom, classroom, is_annual=false, is_embedded=false)
    @entity_configuration = entity_configuration
    @year = year
    @descriptives_exams = descriptives_exams
    @descriptives_values = descriptives_values
    @students = students
    @unity = unity
    @student_enrollment_classroom = student_enrollment_classroom
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

  def write_descriptive_exam(exam_number, exam_value, enroll)
    parecer = exam_value&.value || "Enturmado em #{enroll.joined_at&.to_date}\nDesenturmado em #{enroll.left_at&.to_date}" || return
    
    descriptive_number = @is_annual == true ? '' : exam_number
    exam_cell_header = make_cell(content: "Parecer #{descriptive_number}", size: 8, font_style: :bold, width: 100, borders: [:left, :right], padding: [2, 2, 4, 4], colspan: 2)
    exam_cell = make_cell(content: Nokogiri::HTML(parecer).text, size: 10, width: 100, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 2)
    
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

  end

  def body
    page_content do
      @students.each_with_index do |student, index|
        move_down 10
        identification(student)

        descriptives_values_by_student = @descriptives_values.select{ |item| item.student.id == student.id}
        enrollment_classroom = @student_enrollment_classroom.find{ |item| item.student.id == student.id }
        
        if descriptives_values_by_student.empty?
          move_down 50
        else
          @descriptives_exams.each_with_index do |exam, index|
            value = descriptives_values_by_student.find { |item| item.descriptive_exam_id == exam.id }
            
            write_descriptive_exam(index+1, value, enrollment_classroom)
            
          end          
        end

        move_down 50
        text('___________________________________________                        ___________________________________________', size: 8, align: :center)
        text('        Coordenador(a)                                                           Professor(a)',               size: 10, align: :center)
        
        start_new_page
      end

      
    end
  end

  def footer
    
    page_footer(draw_datetime: true)

  end

end
