require 'action_view'

class ExamStepAverageReport < BaseReport
  include ActionView::Helpers::NumberHelper

  # This number represent how many students are printed on each page
  STUDENT_BY_PAGE_COUNT = 40

  # This factor represent the quantitty of students with social name needed to reduce 1 student by page
  SOCIAL_NAME_REDUCTION_FACTOR = 3

  def self.build(entity_configuration, teacher, year, classroom, discipline, steps, students_enrollments)
    new(:portrait).build(entity_configuration, teacher, year, classroom, discipline, steps, students_enrollments)
  end

  def build(entity_configuration, teacher, year, classroom, discipline, steps, students_enrollments)
    @entity_configuration = entity_configuration
    @teacher = teacher
    @year = year
    @classroom = classroom
    @discipline = discipline
    @steps = steps
    @students_enrollments = students_enrollments
    @active_search = false

    header
    content
    footer

    self
  end

  protected

  attr_accessor :any_student_with_dependence

  private

  def student_enrolled_on_date?(student_id, date)
    student_list(date).include?(student_id)
  end

  def student_list(date)
    student_list ||= {}
    student_list[date] ||= StudentEnrollmentsList.new(
      classroom: classroom,
      discipline: discipline,
      date: date,
      search_type: :by_date,
      show_inactive: false
    ).student_enrollments
    .map(&:student_id)
  end

  def classroom
    @classroom
  end

  def discipline
    @discipline
  end

  def header
    exam_header = make_cell(content: 'Registro de avaliações', size: 12, font_style: :bold, background_color: 'DEDEDE', height: 20, padding: [2, 2, 4, 4], align: :center, colspan: 5)
    begin
      logo_cell = make_cell(image: open(@entity_configuration.logo.url), fit: [50, 50], width: 70, rowspan: 4, position: :center, vposition: :center)
    rescue
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''

    entity_organ_and_unity_cell = make_cell(content: "#{entity_name}\n#{organ_name}\nNome da escola", size: 10, leading: 1.5, align: :center, valign: :center, rowspan: 4, width: 300, padding: [4, 2, 8, 2])
    classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, colspan: 2, borders: [:top, :left, :right], padding: [2, 2, 4, 4], height: 2)
    year_header = make_cell(content: 'Ano letivo', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], height: 2)
    teacher_header = make_cell(content: 'Professor(a)', size: 8, font_style: :bold, colspan: 3, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    classroom_cell = make_cell(content: classroom.description, size: 10, colspan: 2, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], height: 4)
    year_cell = make_cell(content: @year.to_s, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], height: 4)
    teacher_cell = make_cell(content: @teacher.name, size: 10, colspan: 3, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])
    discipline_header = make_cell(content: 'Disciplina', size: 8, font_style: :bold, colspan:1, rowspan:1, borders: [:top, :bottom, :left], padding: [2, 2, 4, 4])
    discipline_cell = make_cell(content: (discipline ? discipline.description : 'Geral'), size: 10, colspan: 4, borders: [:top, :bottom, :right], padding: [0, 2, 4, 4])
    step_header = make_cell(content: 'Etapa', size: 8, colspan:1, rowspan:1, font_style: :bold, borders: [:top, :bottom, :left], padding: [2, 2, 4, 4])
    step_cell = make_cell(content: '', size: 10, colspan: 4, borders: [:bottom, :right], padding: [0, 2, 4, 4])

    first_table_data = [[exam_header],
                        [logo_cell, entity_organ_and_unity_cell, classroom_header, year_header],
                        [classroom_cell, year_cell],
                        [teacher_header],
                        [teacher_cell],
                        [discipline_header, discipline_cell],
                        [step_header, step_cell]]

    page_header do
      table(first_table_data, width: bounds.width, header: true) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def data_table
    @steps.each do |school_calendar_step| 
        averages = {}
        recovery_lowest_note = {}
        school_term_recovery_scores = {}
        self.any_student_with_dependence = false

        @students_enrollments.each do |student_enrollment|
        averages[student_enrollment.id] = StudentAverageCalculator.new(
            student_enrollment.student
        ).calculate(
            classroom,
            discipline,
            school_calendar_step
        )
        end

        exams = []

        avaliations = []
        students = {}

        avaliations << make_cell(content: "1º Bim", font_style: :bold, background_color: 'FFFFFF', align: :center, width: 55)
        

            @students_enrollments.each do |student_enrollment|
                student_id = student_enrollment.student_id
                score = 0 ###########
                student = Student.find(student_id)

                self.any_student_with_dependence = any_student_with_dependence #|| student_has_dependence?(student_enrollment, exam.discipline_id)

                (students[student_enrollment.id] ||= {})[:name] = student.to_s

                students[student_enrollment.id] = {} if students[student_enrollment.id].nil?
                students[student_enrollment.id][:dependence] = students[student_enrollment.id][:dependence] #|| student_has_dependence?(student_enrollment, exam.discipline_id)
                (students[student_enrollment.id][:scores] ||= []) << make_cell(content: localize_score(score), align: :center)
                students[student_enrollment.id][:social_name] = student.social_name
                students[student_enrollment.id][:student_id] = student.id
            end
        

        sequential_number_header = make_cell(content: 'Nº', size: 8, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 15)
        student_name_header = make_cell(content: 'Nome do aluno', size: 8, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 170)
        average_header = make_cell(content: "Média", size: 8, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 30)

        first_headers_and_cells = [sequential_number_header, student_name_header].concat(avaliations)

            lowest_note_header = make_cell(content: "Rec. geral", size: 8, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 30)
            first_headers_and_cells << lowest_note_header

        (5 - avaliations.count).times { first_headers_and_cells << make_cell(content: '', background_color: 'FFFFFF', width: 55) }
        first_headers_and_cells << average_header

        students_cells = []
        students = students.sort_by { |(key, value)| value[:dependence] ? 1 : 0 }
        sequence = 1
        sequence_reseted = false
        students.each do |key, value|
            if !sequence_reseted && value[:dependence]
            sequence = 1
            sequence_reseted = true
            end

            sequence_cell = make_cell(content: sequence.to_s, align: :center)
            student_cells = [sequence_cell, { content: (value[:dependence] ? '* ' : '') + value[:name] }].concat(value[:scores])
            data_column_count = value[:scores].count + (value[:recoveries].nil? ? 0 : value[:recoveries].count)

            student_cells << make_cell(content: "#{recovery_lowest_note[key]}", align: :center)

            number_colums = 5

            (number_colums - data_column_count).times { student_cells << nil }

            recovery_score = if school_term_recovery_scores[key]
                                calculate_recovery_score(value[:student_id], school_term_recovery_scores[key], school_calendar_step)
                            end

            recovery_average = SchoolTermAverageCalculator.new(classroom)
                                                        .calculate(averages[key], recovery_score)
            averages[key] = ScoreRounder.new(classroom, RoundedAvaliations::SCHOOL_TERM_RECOVERY, school_calendar_step)
                                        .round(recovery_average)

            average = averages[key]
            student_cells << make_cell(content: "#{average}", font_style: :bold, align: :center)
            
            students_cells << student_cells

            sequence += 1
        end

        (5 - students_cells.count).times do
            sequence_cell = make_cell(content: (students_cells.count + 1).to_s, align: :center)
            scores = []
            5.times { scores << make_cell(content: '', align: :center) }
            student_cells = [sequence_cell, { content: '' }].concat(scores)
            student_cells << make_cell(content: '', align: :center)
            students_cells << student_cells
        end

        sliced_students_cells = students_cells.each_slice(student_slice_size(students)).to_a

        sliced_students_cells.each_with_index do |students_cells_slice, index|
            data = [
            first_headers_and_cells
            ]
            data.concat(students_cells_slice)

            page_content do
            table(data, row_colors: ['FFFFFF', 'DEDEDE'], cell_style: { size: 8, padding: [2, 2, 2, 2], inline_format: true }, width: bounds.width) do |t|
                t.cells.border_width = 0.25
                t.before_rendering_page do |page|
                page.row(0).border_top_width = 0.25
                page.row(-1).border_bottom_width = 0.25
                page.column(0).border_left_width = 0.25
                page.column(-1).border_right_width = 0.25
                end
            end
            end

            start_new_page if index < sliced_students_cells.count - 1
        end
    end
  end

  def student_transferred?(note_student)
    return note_student unless note_student.transfer_note_id

    return note_student if note_student.note?

    nil
  end

  def calculate_recovery_score(student_id, score, step)
    ComplementaryExamCalculator.new(
      [AffectedScoreTypes::STEP_RECOVERY_SCORE, AffectedScoreTypes::BOTH],
      student_id,
      discipline.id,
      classroom.id,
      step
    ).calculate(score)
  end

  def student_slice_size(students)
    student_with_social_name_count = students.select { |(key, value)|
      value[:social_name].present?
    }.length

    STUDENT_BY_PAGE_COUNT - (student_with_social_name_count / SOCIAL_NAME_REDUCTION_FACTOR)
  end

  def content
    data_table
  end

  def footer
    page_footer do
      repeat(:all) do
        draw_text('Assinatura do(a) professor(a):', size: 8, style: :bold, at: [0, 0])
        draw_text('________________________________', size: 8, at: [0, 8])

        draw_text('Assinatura do(a) coordenador(a):', size: 8, style: :bold, at: [259, 0])
        draw_text('________________________________', size: 8, at: [259, 8])

        draw_text('Data:', size: 8, style: :bold, at: [450, 34])
        draw_text('________________', size: 8, at: [472, 34])
        if @active_search
          draw_text('Legendas: N - Não enturmado, D - Dispensado da avaliação ou da disciplina, B - Busca ativa', size: 8, style: :bold, at: [0, 34])
        else
          draw_text('Legendas: N - Não enturmado, D - Dispensado da avaliação ou da disciplina', size: 8, style: :bold, at: [0, 34])
        end
        draw_text('* Alunos cursando dependência', size: 8, at: [0, 32]) if self.any_student_with_dependence
      end
    end
  end

  def exempted_avaliation?(student_id, avaliation_id)
    avaliation_is_exempted = AvaliationExemption
      .by_student(student_id)
      .by_avaliation(avaliation_id)
      .any?
    avaliation_is_exempted
  end

  def exempted_from_discipline?(student_enrollment, exam)
    discipline_id = exam.discipline.id

    test_date = exam.test_date
    steps_fetcher = StepsFetcher.new(exam.classroom)
    step_number = steps_fetcher.step_by_date(test_date).to_number

    student_enrollment.exempted_disciplines.by_discipline(discipline_id)
                                           .by_step_number(step_number)
                                           .any?
  end

  def recovery_record(record)
    record.class.to_s == "RecoveryDiaryRecord"
  end

  def complementary_exam_record(record)
    record.class.to_s == "ComplementaryExam"
  end

  def school_term_recovery_record(record)
    record.class.to_s == "SchoolTermRecoveryDiaryRecord"
  end

  def localize_score(value)
    return value unless value.is_a? Numeric
    number_with_precision(value, precision: 1)
  end

  def student_has_dependence?(student_enrollment, discipline)
    StudentEnrollmentDependence
      .by_student_enrollment(student_enrollment)
      .by_discipline(discipline)
      .any?
  end

  def exam_description(record)
    if recovery_record(record)
      "Rec. #{record.avaliation_recovery_diary_record.avaliation}\n<font size='7'>#{record.recorded_at.strftime("%d/%m")}</font>"
    elsif complementary_exam_record(record)
      "#{record.complementary_exam_setting.description}\n<font size='7'>#{record.recorded_at.strftime("%d/%m")}\n#{record.complementary_exam_setting.maximum_score}</font>"
    elsif school_term_recovery_record(record)
      "Recuperação da etapa\n<font size='7'>#{record.recorded_at.strftime("%d/%m")}"
    else
      "#{record.avaliation.to_s}\n<font size='7'>#{record.test_date.strftime("%d/%m")}</font>\n<font size='7'>#{record.avaliation.try(:weight)}</font>"
    end
  end
end
