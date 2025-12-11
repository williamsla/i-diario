class PendingRecordsCalculator
  def initialize(unity_id: nil, classroom_id: nil, teacher_id: nil, discipline_id: nil, start_date: nil, end_date: nil, school_year: nil, count_only: false)
    @unity_id = unity_id
    @classroom_id = classroom_id
    @teacher_id = teacher_id
    @discipline_id = discipline_id
    @start_date = start_date || Date.current.beginning_of_year
    @end_date = end_date || Date.current
    @school_year = school_year || Date.current.year
    @count_only = count_only
  end

  def calculate
    results = []
    
    # Se foi passado um discipline_id e pode ser uma área de conhecimento (turma infantil),
    # verificar primeiro se a turma é infantil antes de buscar teacher_discipline_classrooms
    classroom = nil
    is_infantil = false
    
    if @classroom_id.present?
      classroom = Classroom.find_by(id: @classroom_id)
      is_infantil = classroom ? is_infantil_classroom?(classroom) : false
    end
    
    # Se for turma infantil e foi passado um discipline_id (que pode ser knowledge_area_id),
    # processar diretamente sem depender de teacher_discipline_classrooms
    if is_infantil && @discipline_id.present? && @teacher_id.present? && @classroom_id.present?
      unity = classroom.unity
      school_calendar = CurrentSchoolCalendarFetcher.new(unity, classroom, @school_year).fetch
      return results unless school_calendar

      steps_fetcher = StepsFetcher.new(classroom)
      steps = steps_fetcher.steps_by_date_range(@start_date, @end_date)
      
      if steps.blank?
        start_date = @start_date
        end_date = @end_date
      else
        start_date = [steps.map(&:start_at).min, @start_date].max
        end_date = [steps.map(&:end_at).max, @end_date].min
      end

      # Obter frequency_type da turma
      frequency_type_definer = FrequencyTypeDefiner.new(classroom, @teacher_id, nil, year: @school_year)
      frequency_type_definer.define!
      frequency_type = frequency_type_definer.frequency_type
      is_general_frequency = frequency_type == FrequencyTypes::GENERAL

      today = Date.current
      grade_id = classroom.grade_ids.first

      # Calcular dias letivos
      school_day_checker = SchoolDayChecker.new(school_calendar, start_date, grade_id, classroom.id, nil)
      all_school_days = school_day_checker.school_dates_between(start_date, end_date)

      # Buscar áreas de conhecimento do professor na turma
      knowledge_area_ids = KnowledgeArea.by_teacher(@teacher_id)
                                       .by_classroom_id(classroom.id)
                                       .pluck(:id)
      
      # Filtrar pelo knowledge_area_id fornecido
      knowledge_area_ids = knowledge_area_ids.select { |id| id.to_s == @discipline_id.to_s }
      
      # Se não encontrou a área de conhecimento, retornar vazio
      return results if knowledge_area_ids.blank?
      
      # Processar por área de conhecimento
      infantil_results = process_infantil_classroom(classroom, knowledge_area_ids, school_calendar, start_date, end_date, is_general_frequency, all_school_days, today, grade_id, @teacher_id)
      return infantil_results
    end
    
    # Agrupar por classroom para otimizar queries
    tdcs_by_classroom = teacher_discipline_classrooms.group_by { |tdc| tdc.classroom }
    
    tdcs_by_classroom.each do |classroom, tdcs|
      # Cachear dados comuns da turma
      unity = classroom.unity
      school_calendar = CurrentSchoolCalendarFetcher.new(unity, classroom, @school_year).fetch
      next unless school_calendar

      steps_fetcher = StepsFetcher.new(classroom)
      steps = steps_fetcher.steps_by_date_range(@start_date, @end_date)
      
      if steps.blank?
        start_date = @start_date
        end_date = @end_date
      else
        start_date = [steps.map(&:start_at).min, @start_date].max
        end_date = [steps.map(&:end_at).max, @end_date].min
      end

      # Obter frequency_type da turma
      # Usar o primeiro teacher_id para determinar o frequency_type (todos os professores da mesma turma têm o mesmo tipo)
      first_teacher_id = tdcs.first.teacher_id
      frequency_type_definer = FrequencyTypeDefiner.new(classroom, first_teacher_id, nil, year: @school_year)
      frequency_type_definer.define!
      frequency_type = frequency_type_definer.frequency_type
      is_general_frequency = frequency_type == FrequencyTypes::GENERAL

      today = Date.current
      grade_id = classroom.grade_ids.first

      # Calcular dias letivos UMA VEZ para todas as disciplinas da turma
      # Usar a primeira disciplina (geralmente todas têm as mesmas regras de calendário)
      first_discipline_id = tdcs.first.discipline_id
      school_day_checker = SchoolDayChecker.new(school_calendar, start_date, grade_id, classroom.id, first_discipline_id)
      all_school_days = school_day_checker.school_dates_between(start_date, end_date)

      # Verificar se é turma infantil
      is_infantil = is_infantil_classroom?(classroom)

      # Se for turma infantil, buscar áreas de conhecimento ao invés de disciplinas
      if is_infantil
        # Buscar áreas de conhecimento do professor na turma
        teacher_id = tdcs.first.teacher_id
        knowledge_area_ids = KnowledgeArea.by_teacher(teacher_id)
                                         .by_classroom_id(classroom.id)
                                         .pluck(:id)
        
        # Se discipline_id foi fornecido e é um ID de área de conhecimento, filtrar
        if @discipline_id.present?
          knowledge_area_ids = knowledge_area_ids.select { |id| id.to_s == @discipline_id.to_s }
        end
        
        # Para turmas infantis, processar por área de conhecimento
        results.concat(process_infantil_classroom(classroom, knowledge_area_ids, school_calendar, start_date, end_date, is_general_frequency, all_school_days, today, grade_id, teacher_id))
        next # Pular processamento normal de disciplinas
      end

      # Buscar weekdays em batch para todas as disciplinas (sempre necessário para conteúdos)
      discipline_ids = tdcs.map { |tdc| tdc.discipline_id }.uniq
      periods = tdcs.map(&:period).uniq
      all_weekdays, discarded_weekdays = get_all_disciplines_weekdays(classroom.id, discipline_ids, periods)
      
      # Para frequência geral, obter os weekdays de cada professor (todos os dias que ele tem aula na turma)
      teacher_weekdays_by_teacher = {}
      if is_general_frequency
        teacher_ids = tdcs.map { |tdc| tdc.teacher_id }.uniq
        teacher_ids.each do |teacher_id|
          teacher_weekdays_by_teacher[teacher_id] = get_teacher_weekdays(classroom.id, [teacher_id], periods)
        end
      end

      # Buscar frequências e conteúdos em batch para todas as disciplinas (otimização)
      all_frequencies_by_discipline = {}
      all_contents_by_discipline = {}
      
      # Frequências: buscar uma única vez por turma/disciplina (sem filtrar por professor)
      # Isso garante que registros de professores anteriores sejam considerados
      if is_general_frequency
        # Frequências gerais: buscar uma vez para todas as disciplinas
        general_freq_dates = DailyFrequency
          .by_classroom_id(classroom.id)
          .general_frequency
          .by_frequency_date_between(start_date, end_date)
          .where('frequency_date <= ?', today)
          .pluck(:frequency_date)
          .map(&:to_date)
          .to_set
        
        # Para frequências gerais, todas as disciplinas usam o mesmo conjunto
        all_frequencies_by_discipline[:general] = general_freq_dates
      else
        # Frequências por disciplina: buscar todas de uma vez
        frequency_data = DailyFrequency
          .by_classroom_id(classroom.id)
          .where(discipline_id: discipline_ids)
          .by_frequency_date_between(start_date, end_date)
          .where('frequency_date <= ?', today)
          .pluck(:discipline_id, :frequency_date)
        
        all_frequencies_by_discipline = frequency_data
          .group_by { |d| d[0] }
          .transform_values { |dates| dates.map { |d| d[1].to_date }.to_set }
      end
      
      # Conteúdos: buscar uma única vez por turma/disciplina (sem filtrar por professor)
      # Isso garante que registros de professores anteriores sejam considerados
      content_data = DisciplineContentRecord
        .joins(:content_record)
        .where(content_records: { classroom_id: classroom.id })
        .where(discipline_id: discipline_ids)
        .where('content_records.record_date >= ? AND content_records.record_date <= ? AND content_records.record_date <= ?', start_date, end_date, today)
        .pluck(:discipline_id, 'content_records.record_date')
      
      all_contents_by_discipline = content_data
        .group_by { |d| d[0] }
        .transform_values { |dates| dates.map { |d| d[1].to_date }.to_set }

      tdcs.each do |tdc|
        teacher = tdc.teacher
        discipline = tdc.discipline

        # Filtrar apenas disciplinas que não são grouper e não são descriptor
        next if discipline.grouper == true || discipline.descriptor == true

        # Para frequências: se for GENERAL, usar todos os dias letivos (não filtrar por weekdays)
        # Se for BY_DISCIPLINE, filtrar por weekdays da disciplina
        # Para conteúdos: sempre filtrar por weekdays da disciplina
        discipline_weekdays = all_weekdays[discipline.id] || []
        discipline_discarded_weekdays = discarded_weekdays[discipline.id] || []
        
        # Mapear weekdays para números (0=domingo, 1=segunda, etc)
        weekday_numbers = discipline_weekdays.map do |wd|
          case wd
          when 'sunday' then 0
          when 'monday' then 1
          when 'tuesday' then 2
          when 'wednesday' then 3
          when 'thursday' then 4
          when 'friday' then 5
          when 'saturday' then 6
          end
        end.compact
        
        # Mapear weekdays excluídos para números
        discarded_weekday_numbers = discipline_discarded_weekdays.map do |wd|
          case wd
          when 'sunday' then 0
          when 'monday' then 1
          when 'tuesday' then 2
          when 'wednesday' then 3
          when 'thursday' then 4
          when 'friday' then 5
          when 'saturday' then 6
          end
        end.compact
        
        # Obter weekdays do professor específico para frequência geral
        current_teacher_weekdays = is_general_frequency ? (teacher_weekdays_by_teacher[teacher.id] || []) : []
        
        if discipline_weekdays.empty?
          school_days_for_content = []
          # Para frequência geral, usar os weekdays do professor; senão, vazio
          if is_general_frequency
            teacher_weekday_numbers = current_teacher_weekdays.map do |wd|
              case wd
              when 'sunday' then 0
              when 'monday' then 1
              when 'tuesday' then 2
              when 'wednesday' then 3
              when 'thursday' then 4
              when 'friday' then 5
              when 'saturday' then 6
              end
            end.compact
            school_days_for_frequency = teacher_weekday_numbers.any? ? all_school_days.select { |date| teacher_weekday_numbers.include?(date.wday) } : []
          else
            school_days_for_frequency = []
          end
        else
          # Filtrar apenas os dias letivos que correspondem aos dias da semana da disciplina (quadro ativo)
          school_days_for_content = all_school_days.select { |date| weekday_numbers.include?(date.wday) }
          # Para frequência geral, usar os weekdays do professor; senão, usar os da disciplina
          if is_general_frequency
            teacher_weekday_numbers = current_teacher_weekdays.map do |wd|
              case wd
              when 'sunday' then 0
              when 'monday' then 1
              when 'tuesday' then 2
              when 'wednesday' then 3
              when 'thursday' then 4
              when 'friday' then 5
              when 'saturday' then 6
              end
            end.compact
            school_days_for_frequency = teacher_weekday_numbers.any? ? all_school_days.select { |date| teacher_weekday_numbers.include?(date.wday) } : []
          else
            school_days_for_frequency = school_days_for_content
          end
        end
        
        # Obter dias que estão em quadros excluídos
        school_days_discarded = all_school_days.select { |date| discarded_weekday_numbers.include?(date.wday) }

        # Obter frequências registradas (usar dados já carregados em batch)
        if @count_only
          # Modo otimizado: usar dados já carregados em batch
          if is_general_frequency
            frequency_dates_set = all_frequencies_by_discipline[:general] || Set.new
          else
            frequency_dates_set = all_frequencies_by_discipline[discipline.id] || Set.new
          end

          content_dates_set = all_contents_by_discipline[discipline.id] || Set.new

          # Calcular pendências baseado apenas no quadro ativo
          pending_frequency_dates = school_days_for_frequency.select { |date| date <= today && !frequency_dates_set.include?(date) }.to_a
          pending_content_dates = school_days_for_content.select { |date| date <= today && !content_dates_set.include?(date) }.to_a
          
          # Identificar registros em datas de quadro excluído e remover pendência da data mais próxima do quadro ativo
          frequency_dates_in_discarded = frequency_dates_set.select { |date| school_days_discarded.include?(date) && !school_days_for_frequency.include?(date) }
          frequency_dates_in_discarded.each do |discarded_date|
            nearest_pending = find_nearest_pending_date(discarded_date, pending_frequency_dates)
            pending_frequency_dates.delete(nearest_pending) if nearest_pending
          end
          
          content_dates_in_discarded = content_dates_set.select { |date| school_days_discarded.include?(date) && !school_days_for_content.include?(date) }
          content_dates_in_discarded.each do |discarded_date|
            nearest_pending = find_nearest_pending_date(discarded_date, pending_content_dates)
            pending_content_dates.delete(nearest_pending) if nearest_pending
          end
          
          pending_frequency_count = pending_frequency_dates.count
          pending_content_count = pending_content_dates.count
        else
          # Modo completo: buscar todas as datas (sem filtrar por professor)
          if is_general_frequency
            frequencies = DailyFrequency
              .by_classroom_id(classroom.id)
              .general_frequency
              .by_frequency_date_between(start_date, end_date)
              .pluck(:frequency_date)
              .map(&:to_date)
          else
            frequencies = DailyFrequency
              .by_classroom_id(classroom.id)
              .by_discipline_id(discipline.id)
              .by_frequency_date_between(start_date, end_date)
              .pluck(:frequency_date)
              .map(&:to_date)
          end

          # Buscar conteúdos sem filtrar por professor (considera registros de professores anteriores)
          content_records = DisciplineContentRecord
            .joins(:content_record)
            .where(content_records: { classroom_id: classroom.id })
            .where(discipline_id: discipline.id)
            .where('content_records.record_date >= ? AND content_records.record_date <= ?', start_date, end_date)
            .pluck('content_records.record_date')
            .map(&:to_date)

          # Calcular dias pendentes baseado apenas no quadro ativo
          pending_frequency_dates = (school_days_for_frequency - frequencies).select { |date| date <= today }
          pending_content_dates = (school_days_for_content - content_records).select { |date| date <= today }
          
          # Identificar registros em datas de quadro excluído e remover pendência da data mais próxima do quadro ativo
          frequency_dates_in_discarded = frequencies.select { |date| school_days_discarded.include?(date) && !school_days_for_frequency.include?(date) }
          frequency_dates_in_discarded.each do |discarded_date|
            nearest_pending = find_nearest_pending_date(discarded_date, pending_frequency_dates)
            pending_frequency_dates.delete(nearest_pending) if nearest_pending
          end
          
          content_dates_in_discarded = content_records.select { |date| school_days_discarded.include?(date) && !school_days_for_content.include?(date) }
          content_dates_in_discarded.each do |discarded_date|
            nearest_pending = find_nearest_pending_date(discarded_date, pending_content_dates)
            pending_content_dates.delete(nearest_pending) if nearest_pending
          end
          
          pending_frequency_count = pending_frequency_dates.count
          pending_content_count = pending_content_dates.count
        end

        # Calcular carga horária total (usar school_days_for_content para cálculo)
        weekly_hours = calculate_weekly_hours(classroom.id, discipline.id, tdc.period)
        weeks_in_period = calculate_weeks_in_period(start_date, end_date, school_days_for_content)
        total_workload = weekly_hours * weeks_in_period

        result = {
          teacher_id: teacher.id,
          teacher_name: teacher.name,
          discipline_id: discipline.id,
          discipline_name: discipline.to_s,
          classroom_id: classroom.id,
          classroom_name: classroom.description,
          unity_id: unity.id,
          unity_name: unity.name,
          period: tdc.period,
          total_workload: total_workload,
          pending_frequency_count: pending_frequency_count,
          pending_content_count: pending_content_count
        }
        
        # Só incluir as datas se não estiver em modo count_only
        unless @count_only
          result[:pending_frequency_dates] = pending_frequency_dates.sort
          result[:pending_content_dates] = pending_content_dates.sort
        end
        
        results << result
      end
    end

    results
  end

  private

  def teacher_discipline_classrooms
    relation = TeacherDisciplineClassroom
      .includes(:teacher, :discipline, classroom: :unity)
      .joins(:classroom)
      .by_year(@school_year)

    relation = relation.where(classrooms: { unity_id: @unity_id }) if @unity_id.present?
    relation = relation.by_classroom(@classroom_id) if @classroom_id.present?
    relation = relation.by_teacher_id(@teacher_id) if @teacher_id.present?
    relation = relation.by_discipline_id(@discipline_id) if @discipline_id.present?

    relation
  end

  def calculate_weekly_hours(classroom_id, discipline_id, period)
    # Contar aulas semanais da disciplina no quadro de horários
    # Cada registro representa uma aula em um dia da semana
    count = LessonsBoardLessonWeekday
      .joins(teacher_discipline_classroom: [:discipline, :classroom])
      .joins(lessons_board_lesson: [:lessons_board])
      .where(classrooms: { id: classroom_id })
      .where(disciplines: { id: discipline_id })
      .where(lessons_boards: { period: period })
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .count
    
    # Se não encontrar no quadro de horários, retorna 0
    count > 0 ? count : 0
  end

  def calculate_weeks_in_period(start_date, end_date, school_days)
    # Calcular número de semanas baseado nos dias letivos
    # Aproximação: dividir dias letivos por 5 (dias úteis da semana)
    return 0 if school_days.empty?
    
    weeks = (school_days.count.to_f / 5.0).ceil
    [weeks, 1].max # Mínimo de 1 semana
  end

  def get_all_disciplines_weekdays(classroom_id, discipline_ids, periods)
    # Buscar todos os weekdays de uma vez para todas as disciplinas
    # Retorna dois hashes: [active_weekdays, discarded_weekdays]
    # active_weekdays: { discipline_id => [weekdays] } - quadros ativos
    # discarded_weekdays: { discipline_id => [weekdays] } - quadros excluídos
    
    active_result = {}
    discarded_result = {}
    
    # Buscar weekdays de quadros ativos (discarded_at IS NULL)
    weekdays_data_active = LessonsBoardLessonWeekday
      .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
      .joins(:teacher_discipline_classroom)
      .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
      .where(classrooms: { id: classroom_id })
      .where(lessons_boards: { period: periods })
      .where('d.id IN (?)', discipline_ids)
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .where('lessons_boards.discarded_at IS NULL')
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
      .distinct
      .pluck('d.id', :weekday)
    
    weekdays_data_active.each do |discipline_id, weekday|
      active_result[discipline_id] ||= []
      active_result[discipline_id] << weekday unless active_result[discipline_id].include?(weekday)
    end
    
    # Buscar weekdays de quadros excluídos (discarded_at IS NOT NULL)
    weekdays_data_discarded = LessonsBoardLessonWeekday
      .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
      .joins(:teacher_discipline_classroom)
      .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
      .where(classrooms: { id: classroom_id })
      .where(lessons_boards: { period: periods })
      .where('d.id IN (?)', discipline_ids)
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .where('lessons_boards.discarded_at IS NOT NULL')
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
      .distinct
      .pluck('d.id', :weekday)
    
    weekdays_data_discarded.each do |discipline_id, weekday|
      discarded_result[discipline_id] ||= []
      discarded_result[discipline_id] << weekday unless discarded_result[discipline_id].include?(weekday)
    end
    
    # Para disciplinas que não foram encontradas, tenta sem filtrar por período
    missing_discipline_ids = discipline_ids - active_result.keys
    if missing_discipline_ids.any?
      weekdays_data_fallback = LessonsBoardLessonWeekday
        .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
        .joins(:teacher_discipline_classroom)
        .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
        .where(classrooms: { id: classroom_id })
        .where('d.id IN (?)', missing_discipline_ids)
        .where(teacher_discipline_classrooms: { active: true })
        .where(teacher_discipline_classrooms: { discarded_at: nil })
        .where('lessons_boards.discarded_at IS NULL')
        .where.not(weekday: nil)
        .where.not(teacher_discipline_classroom_id: nil)
        .distinct
        .pluck('d.id', :weekday)
      
      weekdays_data_fallback.each do |discipline_id, weekday|
        active_result[discipline_id] ||= []
        active_result[discipline_id] << weekday unless active_result[discipline_id].include?(weekday)
      end
      
      # Buscar também quadros excluídos sem período
      weekdays_data_discarded_fallback = LessonsBoardLessonWeekday
        .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
        .joins(:teacher_discipline_classroom)
        .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
        .where(classrooms: { id: classroom_id })
        .where('d.id IN (?)', missing_discipline_ids)
        .where(teacher_discipline_classrooms: { active: true })
        .where(teacher_discipline_classrooms: { discarded_at: nil })
        .where('lessons_boards.discarded_at IS NOT NULL')
        .where.not(weekday: nil)
        .where.not(teacher_discipline_classroom_id: nil)
        .distinct
        .pluck('d.id', :weekday)
      
      weekdays_data_discarded_fallback.each do |discipline_id, weekday|
        discarded_result[discipline_id] ||= []
        discarded_result[discipline_id] << weekday unless discarded_result[discipline_id].include?(weekday)
      end
    end
    
    [active_result, discarded_result]
  end

  def get_discipline_weekdays(classroom_id, discipline_id, period)
    # Método mantido para compatibilidade, mas agora usa o método otimizado
    all_weekdays, _discarded_weekdays = get_all_disciplines_weekdays(classroom_id, [discipline_id], [period])
    all_weekdays[discipline_id] || []
  end

  def get_teacher_weekdays(classroom_id, teacher_ids, periods)
    # Buscar todos os weekdays de todos os professores na turma
    # Retorna um array único de weekdays: ['monday', 'tuesday', etc]
    
    result = []
    
    # Primeiro tenta com período específico
    weekdays_data = LessonsBoardLessonWeekday
      .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
      .joins(:teacher_discipline_classroom)
      .where(classrooms: { id: classroom_id })
      .where(lessons_boards: { period: periods })
      .where(teacher_discipline_classrooms: { teacher_id: teacher_ids })
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
      .distinct
      .pluck(:weekday)
    
    result.concat(weekdays_data)
    
    # Se não encontrou nada, tenta sem filtrar por período
    if result.empty?
      weekdays_data_fallback = LessonsBoardLessonWeekday
        .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
        .joins(:teacher_discipline_classroom)
        .where(classrooms: { id: classroom_id })
        .where(teacher_discipline_classrooms: { teacher_id: teacher_ids })
        .where(teacher_discipline_classrooms: { active: true })
        .where(teacher_discipline_classrooms: { discarded_at: nil })
        .where.not(weekday: nil)
        .where.not(teacher_discipline_classroom_id: nil)
        .distinct
        .pluck(:weekday)
      
      result.concat(weekdays_data_fallback)
    end
    
    result.uniq
  end

  def find_nearest_pending_date(discarded_date, pending_dates)
    # Encontrar a data pendente mais próxima da data de quadro excluído
    return nil if pending_dates.empty?
    
    # Ordenar datas pendentes
    sorted_pending = pending_dates.sort
    
    # Preferir datas anteriores ou iguais à data do quadro excluído
    before_or_equal = sorted_pending.select { |date| date <= discarded_date }
    return before_or_equal.last if before_or_equal.any?
    
    # Se não houver datas anteriores, usar a mais próxima em geral
    sorted_pending.min_by { |date| (date - discarded_date).abs }
  end

  def is_infantil_classroom?(classroom)
    classroom.classrooms_grades.any? do |classroom_grade|
      grade = classroom_grade.grade
      grade&.description&.match?(/creche|pre|pre-escola|pré|pré-escola|maternal|bercario|berçario|infantil|aee/i)
    end
  end

  def process_infantil_classroom(classroom, knowledge_area_ids, school_calendar, start_date, end_date, is_general_frequency, all_school_days, today, grade_id, teacher_id)
    results = []
    
    return results if knowledge_area_ids.blank?

    teacher = Teacher.find_by(id: teacher_id)
    return results unless teacher

    # Para turmas infantis, não há quadro de aulas por disciplina/área de conhecimento
    # Então usamos todos os dias letivos para conteúdos
    school_days_for_content = all_school_days
    school_days_for_frequency = is_general_frequency ? all_school_days : []

    # Buscar frequências em batch (sem filtrar por professor)
    # Isso garante que registros de professores anteriores sejam considerados
    general_freq_dates = Set.new
    if is_general_frequency
      general_freq_dates = DailyFrequency
        .by_classroom_id(classroom.id)
        .general_frequency
        .by_frequency_date_between(start_date, end_date)
        .where('frequency_date <= ?', today)
        .pluck(:frequency_date)
        .map(&:to_date)
        .to_set
    end

    # Buscar conteúdos por área de conhecimento em batch (sem filtrar por professor)
    # Isso garante que registros de professores anteriores sejam considerados
    content_data = KnowledgeAreaContentRecord
      .joins(:content_record)
      .joins(:knowledge_areas)
      .where(content_records: { classroom_id: classroom.id })
      .where(knowledge_areas: { id: knowledge_area_ids })
      .where('content_records.record_date >= ? AND content_records.record_date <= ? AND content_records.record_date <= ?', start_date, end_date, today)
      .pluck('knowledge_areas.id', 'content_records.record_date')
    
    all_contents_by_knowledge_area = content_data
      .group_by { |d| d[0] }
      .transform_values { |dates| dates.map { |d| d[1].to_date }.to_set }

    # Processar cada área de conhecimento
    knowledge_area_ids.each do |knowledge_area_id|
      knowledge_area = KnowledgeArea.find_by(id: knowledge_area_id)
      next unless knowledge_area

      # Obter frequências registradas
      if @count_only
        if is_general_frequency
          frequency_dates_set = general_freq_dates
        else
          frequency_dates_set = Set.new # Turmas infantis geralmente usam frequência geral
        end

        content_dates_set = all_contents_by_knowledge_area[knowledge_area_id] || Set.new

        # Calcular apenas contadores
        pending_frequency_count = school_days_for_frequency.count { |date| date <= today && !frequency_dates_set.include?(date) }
        pending_content_count = school_days_for_content.count { |date| date <= today && !content_dates_set.include?(date) }
      else
        # Modo completo: buscar todas as datas (sem filtrar por professor)
        if is_general_frequency
          frequencies = DailyFrequency
            .by_classroom_id(classroom.id)
            .general_frequency
            .by_frequency_date_between(start_date, end_date)
            .pluck(:frequency_date)
            .map(&:to_date)
        else
          frequencies = []
        end

        # Buscar conteúdos sem filtrar por professor (considera registros de professores anteriores)
        content_records = KnowledgeAreaContentRecord
          .joins(:content_record)
          .joins(:knowledge_areas)
          .where(content_records: { classroom_id: classroom.id })
          .where(knowledge_areas: { id: knowledge_area_id })
          .where('content_records.record_date >= ? AND content_records.record_date <= ?', start_date, end_date)
          .pluck('content_records.record_date')
          .map(&:to_date)

        pending_frequency_dates = (school_days_for_frequency - frequencies).select { |date| date <= today }
        pending_content_dates = (school_days_for_content - content_records).select { |date| date <= today }
        pending_frequency_count = pending_frequency_dates.count
        pending_content_count = pending_content_dates.count
      end

      # Calcular carga horária (para turmas infantis, usar aproximação)
      weekly_hours = 0 # Turmas infantis não têm quadro de aulas
      weeks_in_period = calculate_weeks_in_period(start_date, end_date, school_days_for_content)
      total_workload = weekly_hours * weeks_in_period

      result = {
        teacher_id: teacher_id,
        teacher_name: teacher.name,
        discipline_id: nil, # Para áreas de conhecimento, não há discipline_id
        knowledge_area_id: knowledge_area_id, # ID da área de conhecimento
        discipline_name: knowledge_area.to_s,
        classroom_id: classroom.id,
        classroom_name: classroom.description,
        unity_id: classroom.unity.id,
        unity_name: classroom.unity.name,
        period: nil,
        total_workload: total_workload,
        pending_frequency_count: pending_frequency_count,
        pending_content_count: pending_content_count
      }
      
      unless @count_only
        result[:pending_frequency_dates] = pending_frequency_dates.sort
        result[:pending_content_dates] = pending_content_dates.sort
      end
      
      results << result
    end

    results
  end
end

