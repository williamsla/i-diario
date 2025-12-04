class PendingRecordsCalculator
  def initialize(unity_id: nil, classroom_id: nil, teacher_id: nil, discipline_id: nil, start_date: nil, end_date: nil, school_year: nil)
    @unity_id = unity_id
    @classroom_id = classroom_id
    @teacher_id = teacher_id
    @discipline_id = discipline_id
    @start_date = start_date || Date.current.beginning_of_year
    @end_date = end_date || Date.current
    @school_year = school_year || Date.current.year
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

      # Buscar weekdays em batch para todas as disciplinas (sempre necessário para conteúdos)
      discipline_ids = tdcs.map { |tdc| tdc.discipline_id }.uniq
      periods = tdcs.map(&:period).uniq
      all_weekdays = get_all_disciplines_weekdays(classroom.id, discipline_ids, periods)
      
      today = Date.current
      grade_id = classroom.grade_ids.first

      tdcs.each do |tdc|
        teacher = tdc.teacher
        discipline = tdc.discipline

        # Obter dias letivos no período (uma vez por disciplina)
        school_day_checker = SchoolDayChecker.new(school_calendar, start_date, grade_id, classroom.id, discipline.id)
        all_school_days = school_day_checker.school_dates_between(start_date, end_date)

        # Para frequências: se for GENERAL, usar todos os dias letivos (não filtrar por weekdays)
        # Se for BY_DISCIPLINE, filtrar por weekdays da disciplina
        # Para conteúdos: sempre filtrar por weekdays da disciplina
        discipline_weekdays = all_weekdays[discipline.id] || []
        
        if discipline_weekdays.empty?
          school_days_for_content = []
          school_days_for_frequency = is_general_frequency ? all_school_days : []
        else
          # Filtrar apenas os dias letivos que correspondem aos dias da semana da disciplina
          school_days_for_content = all_school_days.select do |date|
            weekday_name = date.strftime("%A").downcase
            discipline_weekdays.include?(weekday_name)
          end
          
          # Para frequências: se for GENERAL, usar todos os dias letivos; senão, usar os dias da disciplina
          school_days_for_frequency = is_general_frequency ? all_school_days : school_days_for_content
        end

        # Obter frequências registradas
        if is_general_frequency
          # Se for frequência geral, buscar frequências gerais (discipline_id: nil) que servem para todas as disciplinas
          frequencies = DailyFrequency
            .by_owner_teacher_id(teacher.id)
            .by_classroom_id(classroom.id)
            .general_frequency  # discipline_id: nil, class_number: nil
            .by_frequency_date_between(start_date, end_date)
            .pluck(:frequency_date)
            .map(&:to_date)
        else
          # Se for frequência por disciplina, buscar frequências específicas da disciplina
          frequencies = DailyFrequency
            .by_owner_teacher_id(teacher.id)
            .by_classroom_id(classroom.id)
            .by_discipline_id(discipline.id)
            .by_frequency_date_between(start_date, end_date)
            .pluck(:frequency_date)
            .map(&:to_date)
        end

        # Obter conteúdos registrados (sempre considerar disciplinas do quadro de aulas)
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

        # Calcular carga horária total (usar school_days_for_content para cálculo)
        weekly_hours = calculate_weekly_hours(classroom.id, discipline.id, tdc.period)
        weeks_in_period = calculate_weeks_in_period(start_date, end_date, school_days_for_content)
        total_workload = weekly_hours * weeks_in_period

        results << {
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
          pending_frequency_dates: pending_frequency_dates.sort,
          pending_content_dates: pending_content_dates.sort,
          pending_frequency_count: pending_frequency_dates.count,
          pending_content_count: pending_content_dates.count
        }
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
end

