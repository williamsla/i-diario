require 'roo'
require 'write_xlsx'

class PedagogicalTrackingsController < ApplicationController
  before_action :require_current_year
  before_action :minimum_year

  def index
    my_logger = Logger.new("#{Rails.root}/log/my.log")
    my_logger.info("-----------------------\nACOMPANHAMENTO PEDAGÓGICO")
    
    ini = Time.now
    if (last_refresh = MvwFrequencyBySchoolClassroomTeacher.first&.last_refresh ||
                       MvwContentRecordBySchoolClassroomTeacher.first&.last_refresh)

      @updated_at = last_refresh.to_date.strftime('%d/%m/%Y')
      @updated_at_hour = last_refresh.hour
    end

    unity_id = params.dig(:search, :unity_id).presence || params[:unity_id]

    @start_date = params.dig(:search, :start_date).presence
    start_date = (@start_date || params[:start_date]).try(:to_date)

    @end_date = params.dig(:search, :end_date).presence
    end_date = (@end_date || params[:end_date]).try(:to_date)
    
    if unity_id
      fetch_school_days_by_unity(unity_id, start_date, end_date)

      @school_days = @school_days_by_unity.values.max_by { |school_days_by_unity|
                                            school_days_by_unity[:school_days]
                                          }[:school_days]
      @school_frequency_done_percentage = school_frequency_done_percentage
      @school_content_record_done_percentage = school_content_record_done_percentage
      @unknown_teachers = school_unknown_teacher_frequency_done_percentage
    else
      @school_days = 1
      @school_frequency_done_percentage = 1
      @school_content_record_done_percentage = 1
      @unknown_teachers = 1
    end

    @partial = :schools
    
    @percents = if unity_id
                  @partial = :classrooms
                  @classrooms = Classroom.where(unity_id: unity_id, year: current_user_school_year).ordered

                  paginate(filter(percents(@classrooms.pluck(:id)), params.dig(:filter)))
                else
                  paginate(filter(percents, params.dig(:filter)))
                end
    fim = Time.now
    tempo_resultante = fim - ini
    my_logger.info("tempo carregamento: #{tempo_resultante}")
  end

  def recalculate

    school_calendars = SchoolCalendar.ids

    school_calendars.each do |school_calendar_id|

    SchoolDaysCounterWorker.perform_async(@current_entity.id, school_calendar_id)
    end

    redirect_to pedagogical_trackings_path
  end

  def resume
    unity_id = params[:unity_id]
    classroom_id = params[:classroom_id]
    classroom_id = 0 if classroom_id.blank? || classroom_id == "undefined"
    
    connection = ActiveRecord::Base.connection
    result_school = connection.select_one("SELECT DISTINCT escola.name, 
            CASE 
                WHEN MIN(er.opinion_type)::int > 0 THEN true
                ELSE false
            END AS has_opinion 
        FROM public.unities escola
        INNER JOIN public.classrooms c on c.unity_id = escola.id
		    INNER JOIN public.classrooms_grades cg on cg.classroom_id = c.id
        INNER JOIN public.exam_rules er ON er.id = cg.exam_rule_id
        WHERE escola.id = #{unity_id}
        AND (CASE WHEN #{classroom_id} > 0 THEN c.id = #{classroom_id} ELSE TRUE END)
        GROUP BY escola.name")

    unity_name = result_school['name']
    has_opinion = result_school['has_opinion']
    has_lesson_plan = get_domain_url.include?("belem") || get_domain_url.include?("japaratinga") || get_domain_url.include?("delmiro")
    
    if has_opinion
      subquery_sem_parecer = "select count(distinct se.student_id) - count(distinct des.student_id)
          from public.student_enrollment_classrooms sec
          inner join public.student_enrollments se on se.id = sec.student_enrollment_id and se.active = 1 and se.discarded_at is null
          left join public.descriptive_exams de on de.classroom_id = c.id
          left join public.descriptive_exam_students des on des.descriptive_exam_id = de.id and des.discarded_at is null
          where sec.classroom_code = c.api_code"
    else
      subquery_sem_parecer = "SELECT ''"
    end

    if has_lesson_plan
      subquery_lesson_plan = "select count(lp.id) as qtd
					from public.lesson_plans lp
					left join public.discipline_lesson_plans dlp on dlp.lesson_plan_id = lp.id 	
					left join public.knowledge_area_lesson_plans kalp on kalp.lesson_plan_id = lp.id 	
					where lp.classroom_id = c.id and (case when dlp.id is not null then dlp.discipline_id = d.id else true end)"
    else
      subquery_lesson_plan = "SELECT ''"
    end
    
    rows = connection.select_rows("SELECT distinct c.description as TURMA, upper(t.name) as PROFESSOR, d.description as DISCIPLINA,
			(
          select count(df.id) 
          from public.daily_frequencies df, step_by_classroom(c.id, df.frequency_date) as step
          where df.classroom_id = c.id and df.owner_teacher_id = t.id 
          and (case when df.discipline_id is not null then df.discipline_id = d.id else true end)
          and step.step_number = 1
			) as FREQUENCIA_1,
       (
          select count(df.id) 
          from public.daily_frequencies df, step_by_classroom(c.id, df.frequency_date) as step
          where df.classroom_id = c.id and df.owner_teacher_id = t.id 
          and (case when df.discipline_id is not null then df.discipline_id = d.id else true end)
          and step.step_number = 2
			) as FREQUENCIA_2,
       (
          select count(df.id) 
          from public.daily_frequencies df, step_by_classroom(c.id, df.frequency_date) as step
          where df.classroom_id = c.id and df.owner_teacher_id = t.id 
          and (case when df.discipline_id is not null then df.discipline_id = d.id else true end)
          and step.step_number = 3
			) as FREQUENCIA_3,
       (
          select count(df.id) 
          from public.daily_frequencies df, step_by_classroom(c.id, df.frequency_date) as step
          where df.classroom_id = c.id and df.owner_teacher_id = t.id 
          and (case when df.discipline_id is not null then df.discipline_id = d.id else true end)
          and step.step_number = 4
			) as FREQUENCIA_4,
			(
					#{subquery_lesson_plan}
			) as PLANOS_DE_AULA,
			(
          select coalesce(sum(dcr.class_number), count(cr.id)) as qtd
					from public.content_records cr
					left join public.discipline_content_records dcr on dcr.content_record_id = cr.id
					left join public.knowledge_area_content_records kacr on kacr.content_record_id = cr.id
					where cr.classroom_id = c.id and (case when dcr.id is not null then dcr.discipline_id = d.id else true end)
			) AS AULAS_DADAS,
      (
          select count(ava.id)
          from public.avaliations ava, step_by_classroom(c.id, ava.test_date) as step
          where ava.classroom_id = c.id and ava.discipline_id = d.id
          and step.step_number = 1
			) AS AVALIACOES_1,
			(
          select count(ava.id)
          from public.avaliations ava, step_by_classroom(c.id, ava.test_date) as step
          where ava.classroom_id = c.id and ava.discipline_id = d.id
          and step.step_number = 2
			) AS AVALIACOES_2,
			(
          select count(ava.id)
          from public.avaliations ava, step_by_classroom(c.id, ava.test_date) as step
          where ava.classroom_id = c.id and ava.discipline_id = d.id
          and step.step_number = 3
			) AS AVALIACOES_3,
			(
          select count(ava.id)
          from public.avaliations ava, step_by_classroom(c.id, ava.test_date) as step
          where ava.classroom_id = c.id and ava.discipline_id = d.id
          and step.step_number = 4
			) AS AVALIACOES_4,
			(
        #{subquery_sem_parecer}
			) as ALUNOS_SEM_PARECER
		FROM public.teachers t 
		inner join public.teacher_discipline_classrooms tdc on tdc.teacher_id = t.id and tdc.discarded_at is null and tdc.active = true
		inner join public.classrooms c on c.id = tdc.classroom_id
		inner join public.disciplines d ON d.id = tdc.discipline_id and (d.descriptor = false and d.grouper = false)
		inner join public.unities unity ON unity.id = c.unity_id 
		WHERE tdc.year = #{current_user_school_year} 
		and c.year = #{current_user_school_year}
		and unity.id = #{unity_id}
    and (CASE WHEN #{classroom_id} > 0 THEN c.id = #{classroom_id} ELSE TRUE END)
		GROUP by c.id, c.description,t.id, PROFESSOR, d.id, d.description
		ORDER by c.description asc, PROFESSOR asc, DISCIPLINA asc")

    # Create a new Excel workbook
    date_str = "#{DateTime.now.strftime "%d%m"}#{DateTime.now.year % 100}"
    classroom_str_identifier = classroom_id == 0 ? '' : "T#{classroom_id}-"
    
    filename = "lancamentos-#{date_str}-#{classroom_str_identifier}#{unity_name}.xlsx"
    filename = filename.gsub(" ", "_")

    workbook = WriteXLSX.new("#{Rails.root}/public/relatorios/#{filename}")
    worksheet = workbook.add_worksheet

    # Add and define a format
    format_header = workbook.add_format
    format_header.set_bold
    format_header.set_align('center')
    format_header.set_align('vcenter')
    format_header.set_text_wrap(1)
    format_header.set_size(10)

    format_center = workbook.add_format
    format_center.set_align('center')
    format_center.set_align('vcenter')
    format_center.set_text_wrap(1)
    format_header.set_size(10)

    format_left = workbook.add_format
    format_left.set_align('left')
    format_left.set_align('vcenter')
    format_left.set_text_wrap(1)
    format_header.set_size(10)

    bg_color1 = workbook.add_format(bg_color: '#FFFFFF', pattern: 1)
    bg_color2 = workbook.add_format(bg_color: '#eeeeee', pattern: 1)

    # Congelar a primeira linha
    worksheet.freeze_panes(1, 0)

    worksheet.set_paper(9)             # 9 = A4
    worksheet.fit_to_pages(1, 0)       # Ajusta para caber em 1 página de largura, altura automática

    header_plano_aula = ''
    if has_lesson_plan
      header_plano_aula = 'PLANOS DE AULA'
    end

    header_aluno_sem_parecer = ''
    if has_opinion
      header_aluno_sem_parecer = 'ALUNOS SEM PARECER'
    end
    

    header = ['TURMA','PROFESSOR(A)','DISCIPLINA', 
              'FREQ 1ªUN','FREQ 2ªUN','FREQ 3ªUN','FREQ 4ªUN',
              header_plano_aula, 'CONTEÚDO (horas)',
              'AVA 1ªUN','AVA 2ªUN','AVA 3ªUN','AVA 4ªUN',
               header_aluno_sem_parecer]

    
    worksheet.write(0, 0, header, format_header)
    worksheet.set_row(0, 30)

    list_classrooms = []

    index_row = 1
    rows.each do |row|
      list_classrooms << row[0]
      list_classrooms = list_classrooms.uniq # Remove duplicatas

      cor = if (list_classrooms.size % 2) == 0
              bg_color1
            else
              bg_color2 
            end

      worksheet.set_row(index_row, 32, cor)
      
      index_col = 0
      row.each do |value|
        if value.nil? || value == 0 || value == '0'
          text = '-'
        else
          text = value
        end
        if index_col == 0 # turma
          worksheet.set_column(index_col, index_col, 25, format_center)
        elsif index_col == 1 # professor
          worksheet.set_column(index_col, index_col, 32, format_left)
        elsif index_col == 2 # disciplina
          worksheet.set_column(index_col, index_col, 23, format_left)
        elsif index_col >= 3 && index_col <= 6 # FREQUENCIAS
          worksheet.set_column(index_col, index_col, 5, format_center)
        elsif index_col == 7 # plano de aula
          largura = has_lesson_plan ? 11 : 1
          worksheet.set_column(index_col, index_col, largura, format_center)          
        elsif index_col == 8 # conteúdo
          worksheet.set_column(index_col, index_col, 12, format_center)
        elsif index_col >= 9 && index_col <= 12 # AVALIACÕES
          worksheet.set_column(index_col, index_col, 5, format_center)
        elsif index_col == 13 # alunos sem parecer
          largura = has_opinion ? 11 : 1
          worksheet.set_column(index_col, index_col, largura, format_center)
        else
          next
        end
        worksheet.write(index_row, index_col, text)
        index_col = index_col+1
      end
      index_row = index_row +1
    end

    workbook.close

    file_path = Rails.root.join('public/relatorios', filename)

    return file_path
  end

  def resume_xlsx
    file_path = resume
    filename = File.basename(file_path)

    if File.exist?(file_path)

      send_file file_path,
                filename: filename,
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                disposition: "attachment"
    else
      render plain: "Arquivo não encontrado", status: :not_found
    end    
  end

  def resume_modal
    file_path = resume

    if File.exist?(file_path)
      xlsx = Roo::Excelx.new(file_path)
      @sheet = xlsx.sheet(0)

      # Retorna apenas o HTML da tabela
      render partial: "pedagogical_trackings/table",
             locals: { sheet: @sheet },
             layout: false
    else
      render plain: "Arquivo não encontrado", status: :not_found
    end
  end

  def class_council_modal
    unity_id = params[:unity_id]
    classroom_id = params[:classroom_id].to_i

    return render plain: 'Parâmetros inválidos', status: :bad_request if unity_id.blank?

    classrooms = if classroom_id.positive?
                   Classroom.where(id: classroom_id, unity_id: unity_id, year: current_user_school_year)
                 else
                   Classroom.where(unity_id: unity_id, year: current_user_school_year).ordered
                 end

    return render plain: 'Nenhuma turma encontrada', status: :not_found if classrooms.empty?

    @classrooms = classrooms

    render partial: 'pedagogical_trackings/class_council_modal', layout: false
  rescue StandardError => e
    Rails.logger.error "Erro no class_council_modal: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render plain: "Erro ao carregar relatório: #{e.message}", status: :internal_server_error
  end

  def class_council_pdf
    classroom = Classroom.find_by(
      id: params[:classroom_id],
      unity_id: params[:unity_id],
      year: current_user_school_year
    )

    return render plain: 'Turma não encontrada', status: :not_found if classroom.blank?

    unless ClassCouncilReportDataService.reportable?(classroom)
      report = ClassCouncilReport.build_unavailable(current_entity_configuration, classroom)
      filename = "conselho-de-classe-#{classroom.description.parameterize}-#{Date.current.strftime('%Y%m%d')}.pdf"
      return send_pdf(filename, report.render)
    end

    report_data = ClassCouncilReportDataService.new(classroom).build
    report = ClassCouncilReport.build(current_entity_configuration, report_data)

    filename = "conselho-de-classe-#{classroom.description.parameterize}-#{Date.current.strftime('%Y%m%d')}.pdf"
    send_pdf(filename, report.render)
  rescue StandardError => e
    Rails.logger.error "Erro no class_council_pdf: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render plain: "Erro ao gerar PDF: #{e.message}", status: :internal_server_error
  end

  def frequency_report_modal
    begin
      unity_id = params[:unity_id]
      classroom_id = params[:classroom_id].to_i
      
      return render plain: "Parâmetros inválidos", status: :bad_request if unity_id.blank?

      # Filtro de classificação de risco (por padrão: Abaixo do Mínimo e Crítico)
      selected_classifications = params[:risk_classifications] || ['Abaixo do Mínimo', 'Crítico']
      selected_classifications = [selected_classifications] unless selected_classifications.is_a?(Array)
      @selected_classifications = selected_classifications

      # Filtro principal: escolher qual critério usar
      # 'absences_only': apenas alunos com 3+ faltas nos últimos 15 dias
      # 'low_frequency_only' (padrão): apenas alunos com < 80% de frequência no ano
      # 'both': ambos os critérios (3+ faltas OU < 80%)
      @main_filter = params[:main_filter] || 'low_frequency_only'

      # Data atual e últimos 15 dias
      end_date = Date.current
      start_date_15_days = 15.days.ago.to_date

      # Buscar turmas da unidade
      if classroom_id > 0
        classrooms = Classroom.where(id: classroom_id, unity_id: unity_id, year: current_user_school_year)
      else
        classrooms = Classroom.where(unity_id: unity_id, year: current_user_school_year).ordered
      end

      return render plain: "Nenhuma turma encontrada", status: :not_found if classrooms.empty?

      @classrooms_data = []

      classrooms.each do |classroom|
        # Data de início do ano letivo para esta turma
        steps_fetcher = StepsFetcher.new(classroom)
        school_calendar = steps_fetcher.school_calendar
        year_start_date = if school_calendar&.steps&.any?
                            school_calendar.first_day
                          else
                            Date.new(current_user_school_year, 1, 1)
                          end

        # Buscar alunos ativos da turma na data atual
        student_enrollment_classrooms = StudentEnrollmentClassroom
          .joins(student_enrollment: :student)
          .includes(student_enrollment: :student)
          .by_classroom(classroom.id)
          .by_date(end_date)
          .active
          .order('student_enrollment_classrooms.sequence ASC, students.name ASC')

        # OTIMIZAÇÃO: Usar consultas SQL agregadas para calcular faltas diretamente no banco
        # IMPORTANTE: Contar apenas uma falta por dia (mesmo que o aluno tenha faltado em múltiplas disciplinas)
        # Usar COUNT(DISTINCT frequency_date) para contar dias únicos de falta
        
        # Buscar faltas dos últimos 15 dias agrupadas por aluno (contando dias únicos)
        absences_15_days_by_student = DailyFrequencyStudent
          .joins(:daily_frequency)
          .where(daily_frequencies: { classroom_id: classroom.id, frequency_date: start_date_15_days..end_date })
          .where(active: true)
          .where("COALESCE(daily_frequency_students.present, 'f') = 'f'")
          .group(:student_id)
          .count("DISTINCT daily_frequencies.frequency_date")

        # Buscar faltas do ano inteiro agrupadas por aluno (contando dias únicos)
        absences_year_by_student = DailyFrequencyStudent
          .joins(:daily_frequency)
          .where(daily_frequencies: { classroom_id: classroom.id, frequency_date: year_start_date..end_date })
          .where(active: true)
          .where("COALESCE(daily_frequency_students.present, 'f') = 'f'")
          .group(:student_id)
          .count("DISTINCT daily_frequencies.frequency_date")

        # Buscar presenças do ano inteiro agrupadas por aluno (contando dias únicos)
        presences_year_by_student = DailyFrequencyStudent
          .joins(:daily_frequency)
          .where(daily_frequencies: { classroom_id: classroom.id, frequency_date: year_start_date..end_date })
          .where(active: true)
          .where("daily_frequency_students.present = 't'")
          .group(:student_id)
          .count("DISTINCT daily_frequencies.frequency_date")

        # Buscar última data de presença por aluno (do ano inteiro)
        last_presence_by_student = DailyFrequencyStudent
          .joins(:daily_frequency)
          .where(daily_frequencies: { classroom_id: classroom.id, frequency_date: year_start_date..end_date })
          .where(active: true)
          .where("daily_frequency_students.present = 't'")
          .group(:student_id)
          .maximum('daily_frequencies.frequency_date')

        # Calcular total de dias letivos no período (uma única vez por turma)
        total_school_days = UnitySchoolDay.by_unity_id(classroom.unity_id)
                                          .by_date_between(year_start_date, end_date)
                                          .count

        students_data = []

        student_enrollment_classrooms.each do |enrollment_classroom|
          student = enrollment_classroom.student_enrollment.student
          next unless student.present?

          student_id = student.id

          # Buscar faltas dos últimos 15 dias (já calculadas no banco, contando apenas dias únicos)
          absences_15_days = absences_15_days_by_student[student_id] || 0

          # Buscar faltas e presenças do ano (já calculadas no banco)
          absences_year = absences_year_by_student[student_id] || 0
          presences_year = presences_year_by_student[student_id] || 0
          
          # Calcular percentual de frequência no ano
          # Usar total de registros (presenças + faltas) como base
          total_records = presences_year + absences_year
          frequency_percentage = if total_records > 0
                                   (presences_year.to_f / total_records * 100).round(1)
                                 elsif total_school_days > 0
                                   # Se não há registros, usar dias letivos como base
                                   (presences_year.to_f / total_school_days * 100).round(1)
                                 else
                                   0.0
                                 end

          # Filtrar alunos baseado no filtro principal selecionado
          has_3_or_more_absences = absences_15_days >= 3
          has_low_frequency = frequency_percentage < 80
          
          case @main_filter
          when 'absences_only'
            # Apenas alunos com 3+ faltas nos últimos 15 dias
            next unless has_3_or_more_absences
          when 'low_frequency_only'
            # Apenas alunos com menos de 80% de frequência no ano
            next unless has_low_frequency
          when 'both'
            # Ambos: 3+ faltas OU menos de 80% de frequência
            next unless has_3_or_more_absences || has_low_frequency
          else
            # Padrão: apenas alunos com menos de 80% de frequência no ano
            next unless has_low_frequency
          end
          
          # Data da última presença (já calculada no banco)
          last_presence_date = last_presence_by_student[student_id]
          
          # Classificação de risco baseada no percentual de frequência
          # Considerando que o mínimo é 75%, alunos entre 75% e 80% estão no limite e precisam de atenção
          # >= 80%: Adequado (margem de segurança acima do mínimo)
          # >= 75% e < 80%: Atenção Limite (no limite mínimo, precisa de monitoramento)
          # >= 50% e < 75%: Atenção (abaixo do mínimo, mas não crítico)
          # < 50%: Crítico
          risk_classification = if frequency_percentage >= 80
                                  'Adequado'
                                elsif frequency_percentage >= 75
                                  'Atenção'
                                elsif frequency_percentage >= 50
                                  'Abaixo do Mínimo'
                                else
                                  'Crítico'
                                end

          students_data << {
            student_id: student.id,
            student_name: student.name,
            sequence: enrollment_classroom.sequence || 0,
            absences_15_days: absences_15_days,
            absences_year: absences_year,
            frequency_percentage: frequency_percentage,
            last_presence_date: last_presence_date,
            risk_classification: risk_classification
          }
        end

        # Ordenar por sequência
        students_data.sort_by! { |s| s[:sequence].to_i }

        # Filtrar alunos por classificação de risco selecionada
        filtered_students = students_data.select { |s| @selected_classifications.include?(s[:risk_classification]) }

        @classrooms_data << {
          classroom_id: classroom.id,
          classroom_name: classroom.description,
          students: filtered_students
        }
      end

      render partial: "pedagogical_trackings/frequency_report_table", layout: false
    rescue => e
      Rails.logger.error "Erro no frequency_report_modal: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render plain: "Erro ao carregar relatório: #{e.message}", status: :internal_server_error
    end
  end

  def teachers
    unity_id = params[:unity_id]
    classroom_id = params[:classroom_id]
    teacher_id = params[:teacher_id]
    start_date = params[:start_date].try(:to_date)
    end_date = params[:end_date].try(:to_date)

    fetch_school_days_by_unity(unity_id, start_date, end_date)

    teachers_ids = [teacher_id].compact.presence ||
                   Teacher.by_classroom(classroom_id).by_year(current_user_school_year).pluck(:id).uniq

    @teacher_percents = []

    teachers_ids.each do |teacher_id|
      @teacher_percents << percents([params[:classroom_id]], teacher_id)
    end

    @teacher_percents = @teacher_percents.flatten

    filter_params = params.slice(
      :frequency_operator,
      :frequency_percentage,
      :content_record_operator,
      :content_record_percentage
    )

    @teacher_percents = filter(@teacher_percents, filter_params)

    respond_with @teacher_percents
  end

  private

  def minimum_year
    return if current_user_school_year >= 2020

    flash[:alert] = t('pedagogical_trackings.minimum_year.error')

    redirect_to root_path
  end

  def employee_unities
    return unless current_user.employee?

    roles_ids = Role.where(access_level: AccessLevel::EMPLOYEE).pluck(:id)
    unities_ids = UserRole.where(user_id: current_user.id, role_id: roles_ids).pluck(:unity_id)
    @employee_unities ||= Unity.find(unities_ids)
  end
  helper_method :employee_unities

  def all_unities
    @all_unities ||= Unity.joins(:school_calendars)
                          .where(school_calendars: { year: current_user_school_year })
                          .ordered
  end
  helper_method :all_unities

  def unities_total
    @unities_total ||= @school_days_by_unity.size
  end

  def fetch_school_days_by_unity(unity_id, start_date, end_date)
    return unless unity_id

    unity = Unity.find(unity_id)
    unities = unity || employee_unities || all_unities

    @school_days_by_unity = SchoolDaysCounterService.new(
      unities: unities,
      all_unities_size: all_unities.size,
      start_date: start_date,
      end_date: end_date,
      year: current_user_school_year
    ).school_days
  end

  def school_frequency_done_percentage
    percentage_sum = 0

    # @school_days_by_unity.each do |unity_id, school_days|
      # percentage_sum += frequency_done_percentage(
      #   unity_id,
      #   school_days[:start_date],
      #   school_days[:end_date],
      #   school_days[:school_days]
      # )
    # end

    return 0 if unities_total.zero?

    (percentage_sum.to_f / unities_total).round(2)
  end

  def school_unknown_teacher_frequency_done_percentage
    unknown_teacher_percentage_sum = 0

    # @school_days_by_unity.each do |unity_id, school_days|
    #   unknown_teacher_percentage_sum += unknown_teacher_frequency_done(
    #     unity_id,
    #     school_days[:start_date],
    #     school_days[:end_date],
    #     school_days[:school_days]
    #   )
    # end

    return 0 if unities_total.zero?

    (unknown_teacher_percentage_sum.to_f / unities_total).round(2)
  end

  def school_content_record_done_percentage
    percentage_sum = 0

    # @school_days_by_unity.each do |unity_id, school_days|
    #   percentage_sum += content_record_done_percentage(
    #     unity_id,
    #     school_days[:start_date],
    #     school_days[:end_date],
    #     school_days[:school_days]
    #   )
    # end

    return 0 if unities_total.zero?

    (percentage_sum.to_f / unities_total).round(2)
  end

  def frequency_done_percentage(
    unity_id,
    start_date,
    end_date,
    school_days,
    classroom_id = nil,
    teacher_id = nil
  )
    if teacher_id
      @done_frequencies = MvwFrequencyBySchoolClassroomTeacher.by_unity_id(unity_id)
                                                              .by_date_between(start_date, end_date)
                                                              .by_classroom_id(classroom_id)
                                                              .by_teacher_id(teacher_id)
    elsif classroom_id
      @done_frequencies = MvwFrequencyBySchoolClassroomTeacher.by_unity_id(unity_id)
                                                              .by_date_between(start_date, end_date)
                                                              .by_classroom_id(classroom_id)
    else
      @done_frequencies = MvwFrequencyBySchoolClassroomTeacher.by_unity_id(unity_id)
                                                              .by_date_between(start_date, end_date)
    end
    
    @done_frequencies = @done_frequencies.group_by(&:frequency_date).size

    ((@done_frequencies * 100).to_f / school_days).round(2)
  end

  def content_record_done_percentage(
    unity_id,
    start_date,
    end_date,
    school_days,
    classroom_id = nil,
    teacher_id = nil
  )
    @done_content_records = MvwContentRecordBySchoolClassroomTeacher.by_unity_id(unity_id)
                                                                    .by_date_between(start_date, end_date)
    @done_content_records = @done_content_records.by_classroom_id(classroom_id) if classroom_id
    @done_content_records = @done_content_records.by_teacher_id(teacher_id) if teacher_id
    @done_content_records = @done_content_records.group_by(&:record_date).size

    ((@done_content_records * 100).to_f / school_days).round(2)
  end

  def percents(classrooms_ids = nil, teacher_id = nil)
    percents = []

    if @school_days_by_unity.blank?

      unities = employee_unities || all_unities

      unities.each do |unity|
        if classrooms_ids.present?
          classrooms_ids.each do |classroom_id|
            percents << build_percent_table(
              unity,
              '',
              '',
              100,
              classroom_id,
              teacher_id
            )
          end
        else
          percents << build_percent_table(
            unity,
            '',
            '',
            100
          )
        end
      end
      
    else
      @school_days_by_unity.each do |unity_id, school_days|
        unity = Unity.find(unity_id)

        if classrooms_ids.present?
          classrooms_ids.each do |classroom_id|
            percents << build_percent_table(
              unity,
              school_days[:start_date],
              school_days[:end_date],
              school_days[:school_days],
              classroom_id,
              teacher_id
            )
          end
        else
          percents << build_percent_table(
            unity,
            school_days[:start_date],
            school_days[:end_date],
            school_days[:school_days]
          )
        end
      end
    end

    percents
  end

  def build_percent_table(unity, start_date, end_date, school_days, classroom_id = nil, teacher_id = nil)
    frequency_percentage = frequency_done_percentage(
      unity.id,
      start_date,
      end_date,
      school_days,
      classroom_id,
      teacher_id
    )
    content_record_percentage = content_record_done_percentage(
      unity.id,
      start_date,
      end_date,
      school_days,
      classroom_id,
      teacher_id
    )

    if classroom_id
      classroom = Classroom.find(classroom_id)

      if teacher_id.blank?
        OpenStruct.new(
          unity_id: unity.id,
          unity_name: unity.name,
          classroom_id: classroom.id,
          start_date: start_date,
          end_date: end_date,
          classroom_description: classroom.description,
          frequency_percentage: frequency_percentage,
          content_record_percentage: content_record_percentage
        )
      else
        teacher = Teacher.find(teacher_id)

        OpenStruct.new(
          teacher_id: teacher_id,
          start_date: start_date,
          end_date: end_date,
          teacher_name: teacher.name,
          frequency_percentage: frequency_percentage,
          content_record_percentage: content_record_percentage,
          frequency_days: @done_frequencies,
          content_record_days: @done_content_records
        )
      end
    else
      OpenStruct.new(
        unity_id: unity.id,
        unity_name: unity.name,
        start_date: start_date,
        end_date: end_date,
        frequency_percentage: frequency_percentage,
        content_record_percentage: content_record_percentage
      )
    end
  end

  def filter(percents, params)
    return percents if params.blank?

    params.delete_if do |_filter, value|
      value.blank?
    end

    params.each do |filter, value|
      next if ['frequency_percentage', 'content_record_percentage'].include?(filter)

      percents = percents.select { |school_percent|
        if ['unity_id', 'classroom_id'].include?(filter)
          school_percent.send(filter).to_i == value.to_i
        elsif filter == 'frequency_operator'
          compare(
            school_percent.send(:frequency_percentage).to_f,
            value,
            params[:frequency_percentage].to_f
          )
        else
          compare(
            school_percent.send(:content_record_percentage).to_f,
            value,
            params[:content_record_percentage].to_f
          )
        end
      }
    end

    percents
  end

  def compare(percent, with, value)
    case with
    when ComparativeOperators::EQUALS
      percent == value
    when ComparativeOperators::GREATER_THAN
      percent > value
    when ComparativeOperators::LESS_THAN
      percent < value
    when ComparativeOperators::GREATER_THAN_OR_EQUAL_TO
      percent >= value
    when ComparativeOperators::LESS_THAN_OR_EQUAL_TO
      percent <= value
    end
  end

  def paginate(array)
    return unless array
    Kaminari.paginate_array(array).page(params[:page]).per(10)
  end

  def unknown_teacher_frequency_done(unity_id, start_date, end_date, school_days)
    done_frequencies = DailyFrequency.joins(classroom: :unity)
                                     .by_unity_id(unity_id)
                                     .by_frequency_date_between(start_date, end_date)
                                     .where('EXTRACT(YEAR FROM frequency_date) = ?', current_user_school_year)
                                     .where(owner_teacher_id: nil)
                                     .group_by(&:frequency_date).size

    ((done_frequencies * 100).to_f / school_days).round(2)
  end
end
