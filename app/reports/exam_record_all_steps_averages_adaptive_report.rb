require 'action_view'

# Médias com Recuperação por Bimestre
class ExamRecordAllStepsAveragesAdaptiveReport < BaseReport
  include ActionView::Helpers::NumberHelper

  STUDENT_BY_PAGE_COUNT = 40
  SOCIAL_NAME_REDUCTION_FACTOR = 3
  
  # Cores neutras para distinguir os grupos de colunas (melhor contraste para legibilidade)
  STEP_BG_COLOR = 'FFFFFF'            # Branco para etapas
  FIRST_SEMESTER_BG_COLOR = 'F0F0F0'  # Cinza muito claro para 1º semestre (MP e Rec)
  SECOND_SEMESTER_BG_COLOR = 'F0F0F0'  # Cinza muito claro para 2º semestre (MP e Rec)
  SEMESTER_AVG_BG_COLOR = 'D0D0D0'    # Cinza médio para Média 1º Sem, Média 2º Sem e Rec Final (melhor contraste)
  FINAL_AVG_BG_COLOR = 'B0B0B0'       # Cinza mais escuro para Média Final (melhor contraste)

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
    move_down 10
    content
    footer

    self
  end

  protected

  attr_accessor :any_student_with_dependence

  private

  def header
    exam_header = make_cell(content: 'Registro de avaliações - Médias por Etapa', size: 12, font_style: :bold, background_color: 'DEDEDE', height: 20, padding: [2, 2, 4, 4], align: :center, colspan: 5)
    begin
      logo_cell = make_cell(image: open(@entity_configuration.logo.url), fit: [50, 50], width: 70, rowspan: 4, position: :center, vposition: :center)
    rescue
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''

    entity_organ_and_unity_cell = make_cell(content: "#{entity_name}\n#{organ_name}\n#{@classroom.unity.name}", size: 10, leading: 1.5, align: :center, valign: :center, rowspan: 4, width: 300, padding: [4, 2, 8, 2])
    classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, colspan: 2, borders: [:top, :left, :right], padding: [2, 2, 4, 4], height: 2)
    year_header = make_cell(content: 'Ano letivo', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], height: 2)
    teacher_header = make_cell(content: 'Professor(a)', size: 8, font_style: :bold, colspan: 3, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    classroom_cell = make_cell(content: @classroom.description, size: 10, colspan: 2, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], height: 4)
    year_cell = make_cell(content: @year.to_s, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], height: 4)
    teacher_cell = make_cell(content: @teacher.name, size: 10, colspan: 3, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])
    discipline_header = make_cell(content: 'Disciplina', size: 8, font_style: :bold, colspan: 1, rowspan: 1, borders: [:top, :bottom, :left], padding: [2, 2, 4, 4])
    discipline_cell = make_cell(content: (@discipline ? @discipline.description : 'Geral'), size: 10, colspan: 4, borders: [:top, :bottom, :right], padding: [0, 2, 4, 4])

    first_table_data = [[exam_header],
                        [logo_cell, entity_organ_and_unity_cell, classroom_header, year_header],
                        [classroom_cell, year_cell],
                        [teacher_header],
                        [teacher_cell],
                        [discipline_header, discipline_cell]]

    # Renderizar cabeçalho apenas na primeira página usando repeat
    repeat(lambda { |pg| pg == 1 }) do
      table(first_table_data, width: bounds.width, header: true) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def content
    data_table
  end

  def data_table
    students = {}
    step_averages = {}
    step_recoveries = {}
    final_recoveries = {}
    final_averages = {}

    # Dividir etapas em semestres (para definir cores)
    total_steps = @steps.size
    first_semester_steps = @steps.first((total_steps.to_f / 2).ceil)
    second_semester_steps = @steps.last(total_steps - first_semester_steps.size)

    @students_enrollments.each do |student_enrollment|
      student_id = student_enrollment.student_id
      student = student_enrollment.student

      students[student_enrollment.id] = {
        name: student.to_s,
        social_name: student.social_name,
        student_id: student.id
      }

      # Calcular médias de cada etapa
      step_averages[student_enrollment.id] = []
      step_recoveries[student_enrollment.id] = []
      step_averages_with_recovery = []
      
      @steps.each_with_index do |step, step_index|
        average = StudentAverageCalculator.new(student).calculate(@classroom, @discipline, step)
        step_averages[student_enrollment.id] << average
        
        # Buscar recuperação por etapa
        # Busca recuperações de ETAPA (SchoolTermRecoveryDiaryRecord) pela data de registro dentro do período da etapa
        # Segue o mesmo padrão usado em exam_record_all_steps_averages_report.rb
        step_recovery = SchoolTermRecoveryDiaryRecord
          .joins(recovery_diary_record: :students)
          .where(recovery_diary_records: { classroom_id: @classroom.id, discipline_id: @discipline.id })
          .where(recovery_diary_record_students: { student_id: student_id })
          .where('recovery_diary_records.recorded_at >= ? AND recovery_diary_records.recorded_at <= ?', 
                 step.start_at, step.end_at)
          .order('recovery_diary_records.recorded_at DESC')
          .first
        
        step_recovery_score = nil
        if step_recovery
          recovery_student = step_recovery.recovery_diary_record.students.find_by(student_id: student_id)
          step_recovery_score = recovery_student&.score
        end
        step_recoveries[student_enrollment.id] << step_recovery_score
        
        # Aplicar recuperação de etapa na média usando SchoolTermAverageCalculator
        # Isso garante que a recuperação seja aplicada corretamente conforme a regra da turma
        recovery_score_for_calc = step_recovery_score.present? ? calculate_recovery_score(student_id, step_recovery_score, step) : nil
        average_with_recovery = SchoolTermAverageCalculator.new(@classroom).calculate(average, recovery_score_for_calc)
        step_averages_with_recovery << average_with_recovery
      end

      # Buscar recuperação final
      final_recovery_record = FinalRecoveryDiaryRecord
        .joins(recovery_diary_record: :students)
        .where(recovery_diary_records: { classroom_id: @classroom.id, discipline_id: @discipline.id })
        .where(recovery_diary_record_students: { student_id: student_id })
        .where(school_calendar_id: @classroom.unity.school_calendars.by_year(@year).first&.id)
        .first
      
      final_recovery_score = nil
      if final_recovery_record
        recovery_student = final_recovery_record.recovery_diary_record.students.find_by(student_id: student_id)
        final_recovery_score = recovery_student&.score
      end
      final_recoveries[student_enrollment.id] = final_recovery_score

      # Calcular média final usando as médias já ajustadas pelas recuperações de etapa
      # Notas vazias são consideradas como 0
      all_step_averages = step_averages_with_recovery.map { |v| v.to_f }
      final_average = all_step_averages.any? ? (all_step_averages.sum.to_f / @steps.size.to_f) : nil
      
      # Aplicar recuperação final se houver
      if final_recovery_score.present? && final_recovery_score.to_f > (final_average || 0).to_f
        final_average = final_recovery_score.to_f
      end
      
      final_averages[student_enrollment.id] = final_average ? ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, @steps.last).round(final_average) : nil
    end

    # Construir tabela com recuperação por etapa
    sequential_number_header = make_cell(content: 'Nº', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center)
    student_name_header = make_cell(content: 'Nome do aluno', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center)

    # Headers com recuperação por etapa (sem MP semestral)
    step_headers = []
    @steps.each_with_index do |step, index|
      step_headers << make_cell(content: "#{step.step_number}ª Etapa", size: 7, font_style: :bold, background_color: STEP_BG_COLOR, align: :center)
      rec_bg_color = index < first_semester_steps.size ? FIRST_SEMESTER_BG_COLOR : SECOND_SEMESTER_BG_COLOR
      step_headers << make_cell(content: "Rec\n#{step.step_number}ª", size: 7, font_style: :bold, background_color: rec_bg_color, align: :center, valign: :center)
    end

    # Headers finais
    rec_final_header = make_cell(content: "Rec\nFinal", size: 7, font_style: :bold, background_color: SEMESTER_AVG_BG_COLOR, align: :center, valign: :center)
    final_average_header = make_cell(content: "Média\nFinal", size: 7, font_style: :bold, background_color: FINAL_AVG_BG_COLOR, align: :center, valign: :center)

    headers = [sequential_number_header, student_name_header] + 
              step_headers +
              [rec_final_header, final_average_header]

    students_data = []
    @students_enrollments.each_with_index do |student_enrollment, index|
      row = [make_cell(content: (index + 1).to_s, size: 7, align: :center),
             make_cell(content: students[student_enrollment.id][:name], size: 7, align: :left)]

      # Dados com recuperação por etapa (sem MP semestral)
      @steps.each_with_index do |step, step_index|
        average = step_averages[student_enrollment.id][step_index]
        recovery = step_recoveries[student_enrollment.id][step_index]
        rec_bg_color = step_index < first_semester_steps.size ? FIRST_SEMESTER_BG_COLOR : SECOND_SEMESTER_BG_COLOR
        
        row << make_cell(content: localize_score(average), size: 7, align: :center, background_color: STEP_BG_COLOR)
        row << make_cell(content: localize_score(recovery), size: 7, align: :center, background_color: rec_bg_color)
      end

      # Dados finais
      row << make_cell(content: localize_score(final_recoveries[student_enrollment.id]), size: 7, align: :center, background_color: SEMESTER_AVG_BG_COLOR)
      row << make_cell(content: localize_score(final_averages[student_enrollment.id]), size: 7, align: :center, font_style: :bold, background_color: FINAL_AVG_BG_COLOR)

      students_data << row
    end

    table_data = [headers] + students_data

    table(table_data, width: bounds.width, header: true) do
      cells.border_width = 0.25
      # Não aplicar background_color globalmente na linha 0 para preservar as cores individuais dos cabeçalhos
      row(0).font_style = :bold
    end
  end


  def calculate_recovery_score(student_id, score, step)
    ComplementaryExamCalculator.new(
      [AffectedScoreTypes::STEP_RECOVERY_SCORE, AffectedScoreTypes::BOTH],
      student_id,
      @discipline.id,
      @classroom.id,
      step
    ).calculate(score)
  end

  def localize_score(score)
    return '' if score.blank?
    return score if score == 'D' || score == 'N'

    number_with_precision(score, precision: 1, separator: ',', delimiter: '.')
  end
end

