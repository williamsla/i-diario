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
      all_weekdays = get_all_disciplines_weekdays(classroom.id, discipline_ids, periods)

      # Buscar frequências e conteúdos em batch para todas as disciplinas (otimização)
      teacher_ids = tdcs.map { |tdc| tdc.teacher_id }.uniq
      all_frequencies_by_teacher_discipline = {}
      all_contents_by_teacher_discipline = {}
      
      teacher_ids.each do |teacher_id|
        if is_general_frequency
          # Frequências gerais: buscar uma vez para todas as disciplinas
          general_freq_dates = DailyFrequency
            .by_owner_teacher_id(teacher_id)
            .by_classroom_id(classroom.id)
            .general_frequency
            .by_frequency_date_between(start_date, end_date)
            .where('frequency_date <= ?', today)
            .pluck(:frequency_date)
            .map(&:to_date)
            .to_set
          
          # Para frequências gerais, todas as disciplinas usam o mesmo conjunto
          all_frequencies_by_teacher_discipline[teacher_id] = { general: general_freq_dates }
        else
          # Frequências por disciplina: buscar todas de uma vez
          frequency_data = DailyFrequency
            .by_owner_teacher_id(teacher_id)
            .by_classroom_id(classroom.id)
            .where(discipline_id: discipline_ids)
            .by_frequency_date_between(start_date, end_date)
            .where('frequency_date <= ?', today)
            .pluck(:discipline_id, :frequency_date)
          
          all_frequencies_by_teacher_discipline[teacher_id] = frequency_data
            .group_by { |d| d[0] }
            .transform_values { |dates| dates.map { |d| d[1].to_date }.to_set }
        end
        
        # Conteúdos: buscar todos de uma vez para todas as disciplinas
        content_data = DisciplineContentRecord
          .by_teacher_id(teacher_id)
          .by_classroom_id(classroom.id)
          .where(discipline_id: discipline_ids)
          .by_date_range(start_date, end_date)
          .joins(:content_record)
          .where('content_records.record_date <= ?', today)
          .pluck(:discipline_id, 'content_records.record_date')
        
        all_contents_by_teacher_discipline[teacher_id] = content_data
          .group_by { |d| d[0] }
          .transform_values { |dates| dates.map { |d| d[1].to_date }.to_set }
      end

      tdcs.each do |tdc|
        teacher = tdc.teacher
        discipline = tdc.discipline

        # Para frequências: se for GENERAL, usar todos os dias letivos (não filtrar por weekdays)
        # Se for BY_DISCIPLINE, filtrar por weekdays da disciplina
        # Para conteúdos: sempre filtrar por weekdays da disciplina
        discipline_weekdays = all_weekdays[discipline.id] || []
        
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
        
        if discipline_weekdays.empty?
          school_days_for_content = []
          school_days_for_frequency = is_general_frequency ? all_school_days : []
        else
          # Filtrar apenas os dias letivos que correspondem aos dias da semana da disciplina
          school_days_for_content = all_school_days.select { |date| weekday_numbers.include?(date.wday) }
          
          # Para frequências: se for GENERAL, usar todos os dias letivos; senão, usar os dias da disciplina
          school_days_for_frequency = is_general_frequency ? all_school_days : school_days_for_content
        end

        # Obter frequências registradas (usar dados já carregados em batch)
        if @count_only
          # Modo otimizado: usar dados já carregados em batch
          if is_general_frequency
            frequency_dates_set = all_frequencies_by_teacher_discipline[teacher.id]&.dig(:general) || Set.new
          else
            frequency_dates_set = all_frequencies_by_teacher_discipline[teacher.id]&.dig(discipline.id) || Set.new
          end

          content_dates_set = all_contents_by_teacher_discipline[teacher.id]&.dig(discipline.id) || Set.new

          # Calcular apenas contadores
          pending_frequency_dates = []
          pending_frequency_count = school_days_for_frequency.count { |date| date <= today && !frequency_dates_set.include?(date) }
          
          pending_content_dates = []
          pending_content_count = school_days_for_content.count { |date| date <= today && !content_dates_set.include?(date) }
        else
          # Modo completo: buscar todas as datas
          if is_general_frequency
            frequencies = DailyFrequency
              .by_owner_teacher_id(teacher.id)
              .by_classroom_id(classroom.id)
              .general_frequency
              .by_frequency_date_between(start_date, end_date)
              .pluck(:frequency_date)
              .map(&:to_date)
          else
            frequencies = DailyFrequency
              .by_owner_teacher_id(teacher.id)
              .by_classroom_id(classroom.id)
              .by_discipline_id(discipline.id)
              .by_frequency_date_between(start_date, end_date)
              .pluck(:frequency_date)
              .map(&:to_date)
          end

          content_records = DisciplineContentRecord
            .by_teacher_id(teacher.id)
            .by_classroom_id(classroom.id)
            .by_discipline_id(discipline.id)
            .by_date_range(start_date, end_date)
            .joins(:content_record)
            .pluck('content_records.record_date')
            .map(&:to_date)

          # Calcular dias pendentes
          pending_frequency_dates = (school_days_for_frequency - frequencies).select { |date| date <= today }
          pending_content_dates = (school_days_for_content - content_records).select { |date| date <= today }
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
    # Retorna um hash: { discipline_id => [weekdays] }
    
    result = {}
    
    # Primeiro tenta com período específico
    weekdays_data = LessonsBoardLessonWeekday
      .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
      .joins(:teacher_discipline_classroom)
      .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
      .where(classrooms: { id: classroom_id })
      .where(lessons_boards: { period: periods })
      .where('d.id IN (?)', discipline_ids)
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
      .distinct
      .pluck('d.id', :weekday)
    
    weekdays_data.each do |discipline_id, weekday|
      result[discipline_id] ||= []
      result[discipline_id] << weekday unless result[discipline_id].include?(weekday)
    end
    
    # Para disciplinas que não foram encontradas, tenta sem filtrar por período
    missing_discipline_ids = discipline_ids - result.keys
    if missing_discipline_ids.any?
      weekdays_data_fallback = LessonsBoardLessonWeekday
        .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
        .joins(:teacher_discipline_classroom)
        .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
        .where(classrooms: { id: classroom_id })
        .where('d.id IN (?)', missing_discipline_ids)
        .where(teacher_discipline_classrooms: { active: true })
        .where(teacher_discipline_classrooms: { discarded_at: nil })
        .where.not(weekday: nil)
        .where.not(teacher_discipline_classroom_id: nil)
        .distinct
        .pluck('d.id', :weekday)
      
      weekdays_data_fallback.each do |discipline_id, weekday|
        result[discipline_id] ||= []
        result[discipline_id] << weekday unless result[discipline_id].include?(weekday)
      end
    end
    
    result
  end

  def get_discipline_weekdays(classroom_id, discipline_id, period)
    # Método mantido para compatibilidade, mas agora usa o método otimizado
    all_weekdays = get_all_disciplines_weekdays(classroom_id, [discipline_id], [period])
    all_weekdays[discipline_id] || []
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

    # Buscar frequências em batch
    teacher_frequencies = {}
    if is_general_frequency
      general_freq_dates = DailyFrequency
        .by_owner_teacher_id(teacher_id)
        .by_classroom_id(classroom.id)
        .general_frequency
        .by_frequency_date_between(start_date, end_date)
        .where('frequency_date <= ?', today)
        .pluck(:frequency_date)
        .map(&:to_date)
        .to_set
      
      teacher_frequencies[teacher_id] = { general: general_freq_dates }
    end

    # Buscar conteúdos por área de conhecimento em batch
    content_data = KnowledgeAreaContentRecord
      .by_teacher_id(teacher_id)
      .by_classroom_id(classroom.id)
      .by_knowledge_area_id(knowledge_area_ids)
      .by_date_range(start_date, end_date)
      .joins(:content_record)
      .joins(:knowledge_areas)
      .where('content_records.record_date <= ?', today)
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
          frequency_dates_set = teacher_frequencies[teacher_id]&.dig(:general) || Set.new
        else
          frequency_dates_set = Set.new # Turmas infantis geralmente usam frequência geral
        end

        content_dates_set = all_contents_by_knowledge_area[knowledge_area_id] || Set.new

        # Calcular apenas contadores
        pending_frequency_count = school_days_for_frequency.count { |date| date <= today && !frequency_dates_set.include?(date) }
        pending_content_count = school_days_for_content.count { |date| date <= today && !content_dates_set.include?(date) }
      else
        # Modo completo: buscar todas as datas
        if is_general_frequency
          frequencies = DailyFrequency
            .by_owner_teacher_id(teacher_id)
            .by_classroom_id(classroom.id)
            .general_frequency
            .by_frequency_date_between(start_date, end_date)
            .pluck(:frequency_date)
            .map(&:to_date)
        else
          frequencies = []
        end

        content_records = KnowledgeAreaContentRecord
          .by_teacher_id(teacher_id)
          .by_classroom_id(classroom.id)
          .by_knowledge_area_id(knowledge_area_id)
          .by_date_range(start_date, end_date)
          .joins(:content_record)
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

