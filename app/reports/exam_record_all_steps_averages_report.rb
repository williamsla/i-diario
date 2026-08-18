require 'action_view'

# Médias com Recuperação por Semestre
class ExamRecordAllStepsAveragesReport < BaseReport
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
    first_semester_averages = {}
    second_semester_averages = {}
    first_semester_recoveries = {}
    second_semester_recoveries = {}
    first_semester_final_averages = {}
    second_semester_final_averages = {}
    semester_partial_averages = {}
    semester_recoveries = {}
    semester_averages = {}
    final_recoveries = {}
    final_averages = {}

    # Dividir etapas em semestres (geralmente metade das etapas por semestre)
    total_steps = @steps.size
    two_step_layout = total_steps == 2
    first_semester_steps = @steps.first((total_steps.to_f / 2).ceil)
    second_semester_steps = @steps.last(total_steps - first_semester_steps.size)

    first_recovery_step = SchoolTermRecoveryScoresFetcher.recovery_step_for(@classroom, first_semester_steps)
    second_recovery_step = SchoolTermRecoveryScoresFetcher.recovery_step_for(@classroom, second_semester_steps)
    two_step_recovery_step = two_step_layout ? SchoolTermRecoveryScoresFetcher.recovery_step_for(@classroom, @steps) : nil
    recovery_scores = SchoolTermRecoveryScoresFetcher.new(
      @classroom,
      @discipline,
      [first_recovery_step, second_recovery_step, two_step_recovery_step]
    )
    school_calendar_id = StepsFetcher.new(@classroom).school_calendar&.id

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
      @steps.each do |step|
        # Calcular média localmente primeiro
        average = StudentAverageCalculator.new(student).calculate(@classroom, @discipline, step)
        # Se a média estiver null ou em branco, buscar no i-educar
        if average.blank?
          average = fetch_average_from_ieducar(student_id, step.step_number)
        end
        step_averages[student_enrollment.id] << average
      end

      # Calcular médias parciais dos semestres
      # Notas em branco (nil) devem ser consideradas como 0 na média
      first_semester_values  = step_averages[student_enrollment.id].first(first_semester_steps.size)
      second_semester_values = step_averages[student_enrollment.id].last(second_semester_steps.size)

      # Armazenar valores não arredondados para cálculos posteriores
      first_semester_avg_raw = nil
      second_semester_avg_raw = nil

      if first_semester_values.any?
        first_semester_sum   = first_semester_values.map { |v| v.to_f }.sum
        first_semester_count = first_semester_values.size
        first_semester_avg_raw = first_semester_sum / first_semester_count
        first_semester_averages[student_enrollment.id] = ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, first_semester_steps.last).round(first_semester_avg_raw)
      else
        first_semester_averages[student_enrollment.id] = nil
      end

      if second_semester_values.any?
        second_semester_sum   = second_semester_values.map { |v| v.to_f }.sum
        second_semester_count = second_semester_values.size
        second_semester_avg_raw = second_semester_sum / second_semester_count
        second_semester_averages[student_enrollment.id] = ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, second_semester_steps.last).round(second_semester_avg_raw)
      else
        second_semester_averages[student_enrollment.id] = nil
      end

      rec_first_semester_score = recovery_scores.score_for(student_id, first_recovery_step)
      first_semester_recoveries[student_enrollment.id] = rec_first_semester_score

      rec_second_semester_score = recovery_scores.score_for(student_id, second_recovery_step)
      second_semester_recoveries[student_enrollment.id] = rec_second_semester_score

      # Calcular médias finais dos semestres (aplicando recuperação se houver)
      # Para recuperação semestral, calcular sempre como (recuperação + média parcial) / 2
      # Usar valor não arredondado para comparação e cálculo
      first_semester_final_average = first_semester_avg_raw
      if rec_first_semester_score.present? && first_semester_avg_raw.present?        
        if rec_first_semester_score.to_f > (first_semester_avg_raw || 0).to_f
          first_semester_final_average = (rec_first_semester_score.to_f + first_semester_avg_raw.to_f) / 2.0
        end
      end
      first_semester_final_averages[student_enrollment.id] = first_semester_final_average ? ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, first_semester_steps.last).round(first_semester_final_average) : nil

      second_semester_final_average = second_semester_avg_raw
      if rec_second_semester_score.present? && second_semester_avg_raw.present?
        if rec_second_semester_score.to_f > (second_semester_avg_raw || 0).to_f
          second_semester_final_average = (rec_second_semester_score.to_f + second_semester_avg_raw.to_f) / 2.0
        end
      end
      second_semester_final_averages[student_enrollment.id] = second_semester_final_average ? ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, second_semester_steps.last).round(second_semester_final_average) : nil

      # Buscar recuperação final
      final_recovery_record = FinalRecoveryDiaryRecord
        .joins(recovery_diary_record: :students)
        .where(recovery_diary_records: { classroom_id: @classroom.id, discipline_id: @discipline.id })
        .where(recovery_diary_record_students: { student_id: student_id })
        .where(school_calendar_id: school_calendar_id)
        .first
      
      final_recovery_score = nil
      if final_recovery_record
        recovery_student = final_recovery_record.recovery_diary_record.students.find_by(student_id: student_id)
        final_recovery_score = recovery_student&.score
      end
      final_recoveries[student_enrollment.id] = final_recovery_score

      if two_step_layout
        step_values = step_averages[student_enrollment.id]
        semester_mp_raw = if step_values.any?
                            step_values.map { |value| value.to_f }.sum / step_values.size.to_f
                          end
        semester_partial_averages[student_enrollment.id] = semester_mp_raw ? round_score(semester_mp_raw) : nil

        rec_semester_score = recovery_scores.score_for(student_id, two_step_recovery_step)
        rec_semester_score = rec_first_semester_score if rec_semester_score.blank?
        semester_recoveries[student_enrollment.id] = rec_semester_score

        semester_average_raw = apply_semester_recovery(semester_mp_raw, rec_semester_score)
        semester_averages[student_enrollment.id] = semester_average_raw ? round_score(semester_average_raw) : nil
      else
        mp1 = first_semester_final_averages[student_enrollment.id] || 0
        mp2 = second_semester_final_averages[student_enrollment.id] || 0
        semester_average_raw = (mp1.to_f + mp2.to_f) / 2.0
        semester_averages[student_enrollment.id] = round_score(semester_average_raw)
      end

      final_average = semester_average_raw
      if final_recovery_score.present? && final_recovery_score.to_f > final_average.to_f
        final_average = (final_recovery_score.to_f + final_average.to_f) / 2.0
      end

      final_averages[student_enrollment.id] = final_average ? ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, @steps.last).round(final_average) : nil
    end

    # Construir tabela conforme a imagem
    sequential_number_header = make_cell(content: 'Nº', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center)
    student_name_header = make_cell(content: 'Nome do aluno', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center)

    # Headers das etapas individuais - Branco
    first_semester_step_headers = first_semester_steps.map do |step|
      make_cell(content: "#{step.step_number}ª Etapa", size: 7, font_style: :bold, background_color: STEP_BG_COLOR, align: :center)
    end

    # Headers das etapas individuais - Branco
    second_semester_step_headers = second_semester_steps.map do |step|
      make_cell(content: "#{step.step_number}ª Etapa", size: 7, font_style: :bold, background_color: STEP_BG_COLOR, align: :center)
    end

    # Headers do 1º semestre
    mp_first_sem_header = make_cell(content: "MP\n1º Sem", size: 7, font_style: :bold, background_color: FIRST_SEMESTER_BG_COLOR, align: :center, valign: :center)
    rec_first_sem_header = make_cell(content: "Rec.\n1º Sem", size: 7, font_style: :bold, background_color: FIRST_SEMESTER_BG_COLOR, align: :center, valign: :center)
    final_first_sem_header = make_cell(content: "Média\n1º Sem", size: 7, font_style: :bold, background_color: SEMESTER_AVG_BG_COLOR, align: :center, valign: :center)

    # Headers do 2º semestre
    mp_second_sem_header = make_cell(content: "MP\n2º Sem", size: 7, font_style: :bold, background_color: SECOND_SEMESTER_BG_COLOR, align: :center, valign: :center)
    rec_second_sem_header = make_cell(content: "Rec\n2º Sem", size: 7, font_style: :bold, background_color: SECOND_SEMESTER_BG_COLOR, align: :center, valign: :center)
    final_second_sem_header = make_cell(content: "Média\n2º Sem", size: 7, font_style: :bold, background_color: SEMESTER_AVG_BG_COLOR, align: :center, valign: :center)

    mp_semester_header = make_cell(content: "MP\nSemestre", size: 7, font_style: :bold, background_color: FIRST_SEMESTER_BG_COLOR, align: :center, valign: :center)
    rec_semester_header = make_cell(content: "Rec\nSemestre", size: 7, font_style: :bold, background_color: FIRST_SEMESTER_BG_COLOR, align: :center, valign: :center)
    media_semester_header = make_cell(content: "Média\nSemestre", size: 7, font_style: :bold, background_color: SEMESTER_AVG_BG_COLOR, align: :center, valign: :center)

    # Headers finais
    rec_final_header = make_cell(content: "Rec\nFinal", size: 7, font_style: :bold, background_color: SEMESTER_AVG_BG_COLOR, align: :center, valign: :center)
    final_average_header = make_cell(content: "Média\nFinal", size: 7, font_style: :bold, background_color: FINAL_AVG_BG_COLOR, align: :center, valign: :center)

    headers = if two_step_layout
                # 1ª Etapa | 2ª Etapa | MP Semestre | Rec Semestre | Média Semestre | Rec Final | Média Final
                [sequential_number_header, student_name_header] +
                  first_semester_step_headers +
                  second_semester_step_headers +
                  [mp_semester_header, rec_semester_header, media_semester_header, rec_final_header, final_average_header]
              else
                # 1ª, 2ª, MP 1º Sem, Rec. 1º Sem, Média 1º Sem, 3ª, 4ª, MP 2º Sem, Rec 2º Sem, Média 2º Sem, Rec Final, Média Final
                [sequential_number_header, student_name_header] +
                  first_semester_step_headers +
                  [mp_first_sem_header, rec_first_sem_header, final_first_sem_header] +
                  second_semester_step_headers +
                  [mp_second_sem_header, rec_second_sem_header, final_second_sem_header, rec_final_header, final_average_header]
              end

    students_data = []
    @students_enrollments.each_with_index do |student_enrollment, index|
      first_semester_step_averages = step_averages[student_enrollment.id].first(first_semester_steps.size)
      second_semester_step_averages = step_averages[student_enrollment.id].last(second_semester_steps.size)

      row = [make_cell(content: (index + 1).to_s, size: 7, align: :center),
             make_cell(content: students[student_enrollment.id][:name], size: 7, align: :left)]

      if two_step_layout
        first_semester_step_averages.each do |average|
          row << make_cell(content: localize_score(average), size: 7, align: :center, background_color: STEP_BG_COLOR)
        end
        second_semester_step_averages.each do |average|
          row << make_cell(content: localize_score(average), size: 7, align: :center, background_color: STEP_BG_COLOR)
        end

        row << make_cell(content: localize_score(semester_partial_averages[student_enrollment.id]), size: 7, align: :center, background_color: FIRST_SEMESTER_BG_COLOR)
        row << make_cell(content: localize_score(semester_recoveries[student_enrollment.id]), size: 7, align: :center, background_color: FIRST_SEMESTER_BG_COLOR)
        row << make_cell(content: localize_score(semester_averages[student_enrollment.id]), size: 7, align: :center, background_color: SEMESTER_AVG_BG_COLOR)
      else
        first_semester_step_averages.each do |average|
          row << make_cell(content: localize_score(average), size: 7, align: :center, background_color: STEP_BG_COLOR)
        end

        row << make_cell(content: localize_score(first_semester_averages[student_enrollment.id]), size: 7, align: :center, background_color: FIRST_SEMESTER_BG_COLOR)
        row << make_cell(content: localize_score(first_semester_recoveries[student_enrollment.id]), size: 7, align: :center, background_color: FIRST_SEMESTER_BG_COLOR)
        row << make_cell(content: localize_score(first_semester_final_averages[student_enrollment.id]), size: 7, align: :center, background_color: SEMESTER_AVG_BG_COLOR)

        second_semester_step_averages.each do |average|
          row << make_cell(content: localize_score(average), size: 7, align: :center, background_color: STEP_BG_COLOR)
        end

        row << make_cell(content: localize_score(second_semester_averages[student_enrollment.id]), size: 7, align: :center, background_color: SECOND_SEMESTER_BG_COLOR)
        row << make_cell(content: localize_score(second_semester_recoveries[student_enrollment.id]), size: 7, align: :center, background_color: SECOND_SEMESTER_BG_COLOR)
        row << make_cell(content: localize_score(second_semester_final_averages[student_enrollment.id]), size: 7, align: :center, background_color: SEMESTER_AVG_BG_COLOR)
      end

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


  def localize_score(score)
    return '' if score.blank?
    return score if score == 'D' || score == 'N'

    number_with_precision(score, precision: 1, separator: ',', delimiter: '.')
  end

  def apply_semester_recovery(average, recovery_score)
    return average if average.blank? || recovery_score.blank?
    return (average.to_f + recovery_score.to_f) / 2.0 if recovery_score.to_f > average.to_f

    average
  end

  def round_score(score)
    ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, @steps.last).round(score)
  end

  def fetch_average_from_ieducar(student_id, step_number)
    ieducar_api_configuration = IeducarApiConfiguration.current
    return nil if ieducar_api_configuration.blank?

    fetcher = StudentAverageFromIeducarFetcher.new(ieducar_api_configuration)
    average = fetcher.fetch(student_id, @classroom.id, @discipline.id, step_number)
    
    # Arredondar a média conforme as configurações da turma
    if average.present?
      step = @steps.find { |s| s.step_number == step_number }
      ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, step).round(average) if step
    else
      nil
    end
  rescue StandardError => error
    Rails.logger.error "Erro ao buscar média do i-educar: #{error.message}"
    nil
  end
end

