class PendingRecordsCalculator
  # Áreas/disciplinas com "EIXO" ou "FICHA" no nome não entram em datas pendentes
  # nem no registro de conteúdo por área de conhecimento.
  EXCLUDED_KNOWLEDGE_AREA_NAME_PATTERNS = [
    /eixo/,
    /ficha/
  ].freeze

  def self.reset_pending_records_discipline_cache!
    @knowledge_area_ids_with_fichas = nil
    @knowledge_area_ids_with_grouper = nil
    @infantil_content_knowledge_area_ids = nil
  end

  def self.exclude_pending_record_row?(discipline_name:, knowledge_area_id: nil, discipline_id: nil)
    # Exclui fichas/eixos tanto como disciplina quanto como área de conhecimento
    # (no iEducar cada eixo pode ser uma área com o mesmo nome da ficha).
    return true if discipline_name_excluded?(discipline_name)
    return false if knowledge_area_id.present?

    return false if discipline_id.blank?

    discipline = Discipline.includes(:knowledge_area).find_by(id: discipline_id)
    discipline_excluded_from_pending_records?(discipline)
  end

  def self.discipline_name_excluded?(name)
    return false if name.blank?

    normalized = I18n.transliterate(name.to_s.downcase)
    EXCLUDED_KNOWLEDGE_AREA_NAME_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  def self.discipline_excluded_from_pending_records?(discipline)
    return true if discipline.blank?

    knowledge_area = discipline.knowledge_area
    knowledge_area_id = knowledge_area&.id

    return true if discipline.grouper? || discipline.descriptor?
    return true if knowledge_area&.group_descriptors?
    return true if discipline_name_excluded?(discipline.description)
    return true if infantil_content_knowledge_area_ids.include?(knowledge_area_id)
    return true if knowledge_area_with_conceptual_ficha?(knowledge_area_id)
    return true if knowledge_area_with_grouper_discipline?(knowledge_area_id)

    false
  end

  def self.knowledge_area_with_conceptual_ficha?(knowledge_area_id)
    return false if knowledge_area_id.blank?

    knowledge_area_ids_with_fichas.include?(knowledge_area_id)
  end

  def self.knowledge_area_with_grouper_discipline?(knowledge_area_id)
    return false if knowledge_area_id.blank?

    knowledge_area_ids_with_grouper.include?(knowledge_area_id)
  end

  def self.infantil_content_knowledge_area_ids
    @infantil_content_knowledge_area_ids ||= begin
      infantil_ids = KnowledgeArea
        .where(
          'description ILIKE ? OR description ILIKE ? OR description ILIKE ? OR description ILIKE ?',
          '%educação infantil%',
          '%educacao infantil%',
          '%campos de experiência%',
          '%campos de experiencia%'
        )
        .pluck(:id)

      (infantil_ids + knowledge_area_ids_with_grouper.to_a + knowledge_area_ids_with_fichas.to_a)
        .compact
        .uniq
        .to_set
    end
  end

  def self.knowledge_area_ids_with_fichas
    @knowledge_area_ids_with_fichas ||= Discipline
      .where(
        'description ILIKE ? OR description ILIKE ? OR description ~* ?',
        '%ficha conceitual%',
        '%ficha  conceitual%',
        '\beixo\s+(i{1,3}|iv|v)\s*-'
      )
      .distinct
      .pluck(:knowledge_area_id)
      .to_set
  end

  def self.knowledge_area_ids_with_grouper
    @knowledge_area_ids_with_grouper ||= Discipline.unscoped
      .where(grouper: true)
      .distinct
      .pluck(:knowledge_area_id)
      .to_set
  end

  def initialize(unity_id: nil, classroom_id: nil, teacher_id: nil, discipline_id: nil, start_date: nil, end_date: nil, school_year: nil, count_only: false, include_dates: false)
    @unity_id = unity_id
    @classroom_id = classroom_id
    @teacher_id = teacher_id
    @discipline_id = discipline_id
    @start_date = start_date || Date.current.beginning_of_year
    @end_date = end_date || Date.current
    @school_year = school_year || Date.current.year
    @count_only = count_only
    @include_dates = include_dates
  end

  def calculate
    results = []
    self.class.reset_pending_records_discipline_cache!
    self.class.knowledge_area_ids_with_grouper
    self.class.knowledge_area_ids_with_fichas
    self.class.infantil_content_knowledge_area_ids
    
    # Se foi passado um discipline_id e pode ser uma área de conhecimento (turma infantil),
    # verificar primeiro se a turma é infantil antes de buscar teacher_discipline_classrooms
    classroom = nil
    is_infantil = false
    
    if @classroom_id.present?
      classroom = Classroom.find_by(id: @classroom_id)
      is_infantil = classroom ? is_infantil_classroom?(classroom) : false
    end
    
    # Se for turma infantil (ou multisseriada com área de conhecimento) e foi passado knowledge_area_id,
    # processar diretamente sem depender de teacher_discipline_classrooms
    is_multigrade = classroom ? multigrade_infantil_fundamental_classroom?(classroom) : false
    is_pure_infantil = is_infantil && !is_multigrade
    infantil_knowledge_area_param = infantil_knowledge_area_param?(
      classroom, @teacher_id, @discipline_id
    )

    if @discipline_id.present? && @teacher_id.present? && @classroom_id.present? && classroom &&
       (is_pure_infantil || (is_multigrade && infantil_knowledge_area_param))
      unity = classroom.unity
      school_calendar = CurrentSchoolCalendarFetcher.new(unity, classroom, @school_year).fetch
      return results unless school_calendar

      @current_school_calendar = school_calendar
      @saturdays_mapping = nil

      steps_fetcher = StepsFetcher.new(classroom)
      steps = steps_fetcher.steps_by_date_range(@start_date, @end_date)

      if steps.blank?
        start_date = @start_date
        end_date = @end_date
      else
        start_date = [steps.map(&:start_at).min, @start_date].max
        end_date = [steps.map(&:end_at).max, @end_date].min
      end

      frequency_type_definer = FrequencyTypeDefiner.new(classroom, @teacher_id, nil, year: @school_year)
      frequency_type_definer.define!
      frequency_type = frequency_type_definer.frequency_type
      is_general_frequency = frequency_type == FrequencyTypes::GENERAL

      today = Date.current
      grade_id = classroom.grade_ids.first

      school_day_checker = SchoolDayChecker.new(school_calendar, start_date, grade_id, classroom.id, nil)
      all_school_days = school_day_checker.school_dates_between(start_date, end_date)
      all_school_days = add_saturdays_from_lesson_boards(all_school_days, start_date, end_date, classroom.id)

      knowledge_area_ids = if is_multigrade
                             infantil_knowledge_area_ids_for_classroom(classroom, @teacher_id)
                           else
                             KnowledgeArea.by_teacher(@teacher_id)
                                          .by_classroom_id(classroom.id)
                                          .pluck(:id)
                           end

      knowledge_area_ids = knowledge_area_ids.select { |id| id.to_s == @discipline_id.to_s }
      return results if knowledge_area_ids.blank?

      infantil_results = process_infantil_classroom(
        classroom, knowledge_area_ids, school_calendar, start_date, end_date,
        is_general_frequency, all_school_days, today, grade_id, @teacher_id
      )
      filter_excluded_discipline_results!(infantil_results)
      return infantil_results
    end
    
    # Agrupar por classroom para otimizar queries
    tdcs_by_classroom = teacher_discipline_classrooms.group_by { |tdc| tdc.classroom }
    
    tdcs_by_classroom.each do |classroom, tdcs|
      # Cachear dados comuns da turma
      unity = classroom.unity
      school_calendar = CurrentSchoolCalendarFetcher.new(unity, classroom, @school_year).fetch
      next unless school_calendar

      @current_school_calendar = school_calendar
      @saturdays_mapping = nil

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
      
      # Adicionar sábados que estão no quadro de aulas, mesmo que não sejam dias letivos no calendário
      all_school_days = add_saturdays_from_lesson_boards(all_school_days, start_date, end_date, classroom.id)

      is_infantil = is_infantil_classroom?(classroom)
      is_multigrade = multigrade_infantil_fundamental_classroom?(classroom)

      if is_multigrade
        teacher_id = tdcs.first.teacher_id
        knowledge_area_ids = infantil_knowledge_area_ids_for_classroom(classroom, teacher_id)

        if @discipline_id.present? && infantil_knowledge_area_param?(classroom, teacher_id, @discipline_id)
          knowledge_area_ids = knowledge_area_ids.select { |id| id.to_s == @discipline_id.to_s }
        elsif @discipline_id.present?
          knowledge_area_ids = []
        end

        if knowledge_area_ids.present?
          results.concat(
            process_infantil_classroom(
              classroom, knowledge_area_ids, school_calendar, start_date, end_date,
              is_general_frequency, all_school_days, today, grade_id, teacher_id
            )
          )
        end

        non_infantil_ids = non_infantil_grade_ids(classroom)
        tdcs = tdcs.select { |tdc| non_infantil_ids.include?(tdc.grade_id) }

        infantil_ka_ids = infantil_knowledge_area_ids_for_classroom(classroom, teacher_id)
        if infantil_ka_ids.present?
          infantil_discipline_ids = Discipline.where(knowledge_area_id: infantil_ka_ids).pluck(:id)
          tdcs = tdcs.reject { |tdc| infantil_discipline_ids.include?(tdc.discipline_id) }
        end

        next if tdcs.blank?
      elsif is_infantil
        teacher_id = tdcs.first.teacher_id
        knowledge_area_ids = KnowledgeArea.by_teacher(teacher_id)
                                         .by_classroom_id(classroom.id)
                                         .pluck(:id)

        if @discipline_id.present?
          knowledge_area_ids = knowledge_area_ids.select { |id| id.to_s == @discipline_id.to_s }
        end

        results.concat(
          process_infantil_classroom(
            classroom, knowledge_area_ids, school_calendar, start_date, end_date,
            is_general_frequency, all_school_days, today, grade_id, teacher_id
          )
        )
        next
      end

      # Ignorar agrupadores (grouper), descritores (fichas conceituais) e eixos de áreas com group_descriptors
      tdcs = tdcs.reject { |tdc| excluded_discipline_for_pending_records?(tdc.discipline) }
      next if tdcs.blank?

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

      # Agrupar por disciplina para evitar duplicatas em turmas multisseriadas
      # Em turmas multisseriadas, o mesmo professor pode ter a mesma disciplina para diferentes séries
      # Queremos mostrar apenas uma vez por disciplina
      tdcs_by_discipline = tdcs.group_by { |tdc| tdc.discipline_id }
      
      tdcs_by_discipline.each do |discipline_id, discipline_tdcs|
        # Usar o primeiro tdc da disciplina (todos têm a mesma disciplina, professor e turma)
        tdc = discipline_tdcs.first
        teacher = tdc.teacher
        discipline = tdc.discipline

        next if excluded_discipline_for_pending_records?(discipline)

        # Para frequências: se for GENERAL, usar todos os dias letivos (não filtrar por weekdays)
        # Se for BY_DISCIPLINE, filtrar por weekdays da disciplina
        # Para conteúdos: sempre filtrar por weekdays da disciplina
        discipline_weekdays = all_weekdays[discipline.id] || []
        discipline_discarded_weekdays = discarded_weekdays[discipline.id] || []
        
        # Se não encontrou weekdays na busca em batch, tentar buscar diretamente para esta disciplina
        if discipline_weekdays.empty?
          # Primeiro tenta com período
          discipline_weekdays_direct, discipline_discarded_weekdays_direct = get_all_disciplines_weekdays(classroom.id, [discipline.id], periods)
          discipline_weekdays = discipline_weekdays_direct[discipline.id] || []
          discipline_discarded_weekdays = discipline_discarded_weekdays_direct[discipline.id] || []
          
          # Se ainda não encontrou, tenta sem período
          if discipline_weekdays.empty?
            discipline_weekdays_direct, discipline_discarded_weekdays_direct = get_all_disciplines_weekdays(classroom.id, [discipline.id], nil)
            discipline_weekdays = discipline_weekdays_direct[discipline.id] || []
            discipline_discarded_weekdays = discipline_discarded_weekdays_direct[discipline.id] || []
          end
        end
        
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
        
        # Sem weekdays no ativo nem no arquivado: fallback por lançamentos existentes
        if discipline_weekdays.empty? && discipline_discarded_weekdays.empty?
          # Verificar se há frequências ou conteúdos registrados para esta disciplina
          # IMPORTANTE: Verificar ANTES de calcular school_days, mas DEPOIS de all_frequencies_by_discipline ser calculado
          frequency_dates_set_for_check = if is_general_frequency
            all_frequencies_by_discipline[:general] || Set.new
          else
            all_frequencies_by_discipline[discipline.id] || Set.new
          end
          
          content_dates_set_for_check = all_contents_by_discipline[discipline.id] || Set.new
          
          # Se não encontrou no batch, buscar diretamente para esta disciplina
          if frequency_dates_set_for_check.empty? && !is_general_frequency
            frequency_dates_set_for_check = DailyFrequency
              .by_classroom_id(classroom.id)
              .where(discipline_id: discipline.id)
              .by_frequency_date_between(start_date, end_date)
              .where('frequency_date <= ?', today)
              .pluck(:frequency_date)
              .map(&:to_date)
              .to_set
          end
          
          if content_dates_set_for_check.empty?
            content_dates_set_for_check = DisciplineContentRecord
              .joins(:content_record)
              .where(content_records: { classroom_id: classroom.id })
              .where(discipline_id: discipline.id)
              .where('content_records.record_date >= ? AND content_records.record_date <= ? AND content_records.record_date <= ?', start_date, end_date, today)
              .pluck('content_records.record_date')
              .map(&:to_date)
              .to_set
          end
          
          has_recorded_frequencies = frequency_dates_set_for_check.any?
          has_recorded_contents = content_dates_set_for_check.any?
          
          # Se há frequências ou conteúdos registrados, usar todos os dias letivos como fallback
          # Isso garante que não perdemos pendências quando há um problema na busca de weekdays
          if has_recorded_frequencies || has_recorded_contents
            school_days_for_content = all_school_days
            school_days_for_frequency = all_school_days
          else
            # Se não há registros e não há weekdays, não há pendências
            school_days_for_content = []
            school_days_for_frequency = []
          end
        else
          # data <= arquivamento (até quando funcionou) => arquivado; depois => ativo
          archive_date = lessons_board_archive_date(classroom.id)
          school_days_for_content = school_days_by_board_archive_date(
            all_school_days, weekday_numbers, discarded_weekday_numbers, archive_date
          )
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
            school_days_for_frequency = teacher_weekday_numbers.any? ? all_school_days.select { |date| teacher_weekday_numbers.include?(get_equivalent_weekday_number(date)) } : []
          else
            school_days_for_frequency = school_days_for_content
          end
        end
        
        # Obter dias que estão em quadros excluídos
        # IMPORTANTE: Para sábados mapeados, usar o dia equivalente ao invés do próprio sábado
        school_days_discarded = all_school_days.select { |date| discarded_weekday_numbers.include?(get_equivalent_weekday_number(date)) }
        optional_holiday_makeup_dates = Set.new

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
          
          # Incluir registros que estão em dias de quadro excluído, mesmo que também estejam no quadro ativo
          # Isso permite compensar pendências quando há registro em um dia que está em ambos os quadros
          frequency_dates_in_discarded = frequency_dates_set.select { |date| school_days_discarded.include?(date) }
          
          # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
          # IMPORTANTE: Só remover se realmente houver um registro em um quadro excluído que compense a pendência
          removed_frequency_count = 0
          # Só verificar compensação se houver registros em quadros excluídos
          if frequency_dates_in_discarded.any? && discarded_weekday_numbers.any?
            pending_frequency_dates.reject! do |pending_date|
              has_discarded_in_same_week = has_record_in_same_week_from_discarded_board?(
                pending_date, 
                frequency_dates_in_discarded.to_a, 
                school_days_discarded, 
                classroom, 
                discipline, 
                is_general_frequency, 
                today,
                discarded_weekday_numbers
              )
              if has_discarded_in_same_week
                pending_week = get_week_number(pending_date)
                removed_frequency_count += 1
              end
              has_discarded_in_same_week
            end
          end
          
          # Identificar registros em datas de quadro excluído
          # Incluir registros que estão em dias de quadro excluído, mesmo que também estejam no quadro ativo
          content_dates_in_discarded = content_dates_set.select { |date| school_days_discarded.include?(date) }
          
          # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
          # IMPORTANTE: Só remover se realmente houver um registro em um quadro excluído que compense a pendência
          removed_content_count = 0
          # Só verificar compensação se houver registros em quadros excluídos
          if content_dates_in_discarded.any? && discarded_weekday_numbers.any?
            pending_content_dates.reject! do |pending_date|
              has_discarded_in_same_week = has_content_record_in_same_week_from_discarded_board?(
                pending_date, 
                content_dates_in_discarded.to_a, 
                school_days_discarded, 
                classroom, 
                discipline, 
                today,
                discarded_weekday_numbers
              )
              if has_discarded_in_same_week
                pending_week = get_week_number(pending_date)
                removed_content_count += 1
              end
              has_discarded_in_same_week
            end
          end
          
          # Filtrar sábados pendentes baseado em eventos cadastrados
          pending_frequency_dates = filter_saturdays_by_events(pending_frequency_dates, classroom, school_calendar)
          pending_content_dates = filter_saturdays_by_events(pending_content_dates, classroom, school_calendar)

          # Excluir datas de falta do professor (aula não realizada) e incluir datas de reposição
          apply_teacher_absences!(
            pending_frequency_dates, pending_content_dates,
            classroom, discipline, teacher, start_date, end_date, today,
            frequency_dates_set: frequency_dates_set,
            content_dates_set: content_dates_set
          )
          optional_holiday_makeup_dates = apply_optional_holidays!(
            pending_frequency_dates, pending_content_dates,
            classroom, discipline_tdcs.first.period, start_date, end_date, today,
            frequency_dates_set: frequency_dates_set,
            content_dates_set: content_dates_set
          )

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
          
          # Identificar registros em datas de quadro excluído
          # Identificar registros em datas de quadro excluído
          # Incluir registros que estão em dias de quadro excluído, mesmo que também estejam no quadro ativo
          frequency_dates_in_discarded = frequencies.select { |date| school_days_discarded.include?(date) }
    
          # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
          removed_frequency_count = 0
          pending_frequency_dates.reject! do |pending_date|
            has_discarded_in_same_week = has_record_in_same_week_from_discarded_board?(
              pending_date, 
              frequency_dates_in_discarded.to_a, 
              school_days_discarded, 
              classroom, 
              discipline, 
              is_general_frequency, 
              today,
              discarded_weekday_numbers
            )
            if has_discarded_in_same_week
              pending_week = get_week_number(pending_date)
              removed_frequency_count += 1
            end
            has_discarded_in_same_week
          end
          
          # Identificar registros em datas de quadro excluído
          # Incluir registros que estão em dias de quadro excluído, mesmo que também estejam no quadro ativo
          content_dates_in_discarded = content_records.select { |date| school_days_discarded.include?(date) }
          
          # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
          removed_content_count = 0
          pending_content_dates.reject! do |pending_date|
            has_discarded_in_same_week = has_content_record_in_same_week_from_discarded_board?(
              pending_date, 
              content_dates_in_discarded.to_a, 
              school_days_discarded, 
              classroom, 
              discipline, 
              today,
              discarded_weekday_numbers
            )
            if has_discarded_in_same_week
              pending_week = get_week_number(pending_date)
              removed_content_count += 1
            end
            has_discarded_in_same_week
          end
          
          # Filtrar sábados pendentes baseado em eventos cadastrados
          pending_frequency_dates = filter_saturdays_by_events(pending_frequency_dates, classroom, school_calendar)
          pending_content_dates = filter_saturdays_by_events(pending_content_dates, classroom, school_calendar)

          # Excluir datas de falta do professor (aula não realizada) e incluir datas de reposição
          apply_teacher_absences!(
            pending_frequency_dates, pending_content_dates,
            classroom, discipline, teacher, start_date, end_date, today,
            frequency_dates_set: frequencies,
            content_dates_set: content_records
          )
          optional_holiday_makeup_dates = apply_optional_holidays!(
            pending_frequency_dates, pending_content_dates,
            classroom, discipline_tdcs.first.period, start_date, end_date, today,
            frequency_dates_set: frequencies,
            content_dates_set: content_records
          )

          pending_frequency_count = pending_frequency_dates.count
          pending_content_count = pending_content_dates.count
        end

        # Calcular carga horária total (usar school_days_for_content para cálculo)
        # Para turmas multisseriadas, usar o período do primeiro tdc (ou calcular a média se necessário)
        # Mas como estamos agrupando por disciplina, usar o período do primeiro tdc é suficiente
        period_for_calculation = discipline_tdcs.first.period
        weekly_hours = calculate_weekly_hours(classroom.id, discipline.id, period_for_calculation)
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
          period: period_for_calculation,
          total_workload: total_workload,
          in_lessons_board: discipline_weekdays.any?,
          pending_frequency_count: pending_frequency_count,
          pending_content_count: pending_content_count
        }
        
        # Incluir datas quando não for count_only ou quando include_dates (evita chamada /dates no frontend)
        if !@count_only || @include_dates
          result[:pending_frequency_dates] = pending_frequency_dates.sort
          result[:pending_content_dates] = pending_content_dates.sort
          result[:optional_holiday_makeup_dates] = optional_holiday_makeup_dates.to_a
        end
        
        results << result
      end
    end

    filter_excluded_discipline_results!(results)
    results
  end

  private

  # Remove das pendências as datas em que o professor faltou (aula não realizada)
  # e adiciona as datas de reposição como pendência (apenas as que ainda não têm frequência/conteúdo registrados)
  def apply_teacher_absences!(pending_frequency_dates, pending_content_dates,
                              classroom, discipline, teacher, start_date, end_date, today,
                              frequency_dates_set: nil, content_dates_set: nil)
    absence_dates = TeacherAbsence.absence_dates_for(
      classroom_id: classroom.id,
      discipline_id: discipline.id,
      teacher_id: teacher.id,
      start_date: start_date,
      end_date: end_date,
      class_number: nil,
      unity_id: classroom.unity_id
    )
    make_up_dates = TeacherAbsence.make_up_dates_for(
      classroom_id: classroom.id,
      discipline_id: discipline.id,
      teacher_id: teacher.id,
      start_date: start_date,
      end_date: end_date,
      class_number: nil,
      unity_id: classroom.unity_id
    )
    make_up_to_add = make_up_dates.select { |d| d <= today }

    pending_frequency_dates.reject! { |d| absence_dates.include?(d) }
    pending_content_dates.reject! { |d| absence_dates.include?(d) }

    # Só inclui data de reposição como pendente se ainda não tiver frequência/conteúdo registrados
    freq_set = frequency_dates_set || []
    content_set = content_dates_set || []
    make_up_to_add.each do |d|
      pending_frequency_dates << d unless pending_frequency_dates.include?(d) || freq_set.include?(d)
      pending_content_dates << d unless pending_content_dates.include?(d) || content_set.include?(d)
    end
    pending_frequency_dates.sort!
    pending_content_dates.sort!
  end

  def apply_optional_holidays!(pending_frequency_dates, pending_content_dates,
                               classroom, period, start_date, end_date, today,
                               frequency_dates_set: nil, content_dates_set: nil)
    holiday_dates = OptionalHoliday.holiday_dates_for(
      classroom: classroom,
      start_date: start_date,
      end_date: end_date,
      period: period,
      unity_id: classroom.unity_id
    )
    make_up_dates = OptionalHoliday.make_up_dates_for(
      classroom: classroom,
      start_date: start_date,
      end_date: end_date,
      period: period,
      unity_id: classroom.unity_id
    )
    make_up_to_add = make_up_dates.select { |date| date <= today }

    pending_frequency_dates.reject! { |date| holiday_dates.include?(date) }
    pending_content_dates.reject! { |date| holiday_dates.include?(date) }

    freq_set = frequency_dates_set || []
    content_set = content_dates_set || []
    make_up_to_add.each do |date|
      pending_frequency_dates << date unless pending_frequency_dates.include?(date) || freq_set.include?(date)
      pending_content_dates << date unless pending_content_dates.include?(date) || content_set.include?(date)
    end
    pending_frequency_dates.sort!
    pending_content_dates.sort!
    make_up_dates
  end

  def teacher_discipline_classrooms
    relation = TeacherDisciplineClassroom
      .includes(:teacher, discipline: :knowledge_area, classroom: :unity)
      .joins(:classroom)
    
    # Filtrar por ano - converter para string se necessário, pois o campo year pode ser string
    if @school_year.present?
      year_value = @school_year.to_s
      relation = relation.where(year: year_value)
    end

    relation = relation.where(classrooms: { unity_id: @unity_id }) if @unity_id.present?
    relation = relation.by_classroom(@classroom_id) if @classroom_id.present?
    relation = relation.by_teacher_id(@teacher_id) if @teacher_id.present?
    relation = relation.by_discipline_id(@discipline_id) if @discipline_id.present?

    relation
  end

  # Agrupadores (grouper), descritores/fichas conceituais e disciplinas de áreas com
  # group_descriptors não entram em datas pendentes — o lançamento é pela área de conhecimento.
  def excluded_discipline_for_pending_records?(discipline)
    self.class.discipline_excluded_from_pending_records?(discipline)
  end

  def filter_excluded_discipline_results!(results)
    results.reject! do |result|
      self.class.exclude_pending_record_row?(
        discipline_name: result[:discipline_name],
        knowledge_area_id: result[:knowledge_area_id],
        discipline_id: result[:discipline_id]
      )
    end
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

  def get_all_disciplines_weekdays(classroom_id, discipline_ids, periods, teacher_id = nil)
    # Buscar todos os weekdays de uma vez para todas as disciplinas
    # Retorna dois hashes: [active_weekdays, discarded_weekdays]
    # active_weekdays: { discipline_id => [weekdays] } - quadros ativos
    # discarded_weekdays: { discipline_id => [weekdays] } - quadros excluídos
    # IMPORTANTE: Não filtra por teacher_id nos weekdays para garantir que se dois professores
    # têm a mesma disciplina, ambos vejam os mesmos dias pendentes, independente de qual
    # professor está associado ao weekday no quadro de aulas
    # O parâmetro teacher_id é mantido para compatibilidade, mas não é usado aqui
    
    active_result = {}
    discarded_result = {}
    
    # Buscar weekdays de quadros ativos (discarded_at IS NULL)
    # Não filtrar por teacher_id - buscar weekdays de todos os professores que têm a disciplina
    query_active = LessonsBoardLessonWeekday
      .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
      .joins(:teacher_discipline_classroom)
      .joins('INNER JOIN disciplines d ON d.id = teacher_discipline_classrooms.discipline_id')
      .where(classrooms: { id: classroom_id })
      .where('d.id IN (?)', discipline_ids)
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .where('lessons_boards.discarded_at IS NULL')
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
    
    # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
    if @school_year.present?
      query_active = query_active.where(classrooms: { year: @school_year })
    end
    
    # Filtrar por período apenas se períodos foram fornecidos e não estão vazios
    if periods.present? && periods.any? { |p| p.present? }
      query_active = query_active.where(lessons_boards: { period: periods })
    end
    
    weekdays_data_active = query_active.distinct.pluck('d.id', :weekday)
    
    weekdays_data_active.each do |discipline_id, weekday|
      active_result[discipline_id] ||= []
      active_result[discipline_id] << weekday unless active_result[discipline_id].include?(weekday)
    end
    
    # Buscar weekdays de quadros excluídos (discarded_at IS NOT NULL)
    # Usar unscoped para ignorar default_scope e joins diretos nas tabelas
    # Verificar primeiro se há quadros excluídos no banco
    archived_since = effective_archived_since(classroom_id)
    sql_check = <<-SQL
      SELECT COUNT(*) 
      FROM lessons_boards lb
      INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id
      WHERE cg.classroom_id = #{classroom_id}
      AND lb.discarded_at IS NOT NULL
      #{archived_since ? "AND lb.discarded_at >= '#{archived_since}'" : ''}
    SQL
    discarded_boards_count = ActiveRecord::Base.connection.exec_query(sql_check).first&.dig('count') || 0
    
    # Usar unscoped para ignorar default_scope do LessonsBoardLessonWeekday
    # Não filtrar por teacher_id - buscar weekdays de todos os professores que têm a disciplina
    query_discarded = LessonsBoardLessonWeekday.unscoped
      .joins('INNER JOIN lessons_board_lessons lbl ON lbl.id = lessons_board_lesson_weekdays.lessons_board_lesson_id')
      .joins('INNER JOIN lessons_boards lb ON lb.id = lbl.lessons_board_id AND lb.discarded_at IS NOT NULL')
      .joins('INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id')
      .joins('INNER JOIN classrooms ON classrooms.id = cg.classroom_id')
      .joins('INNER JOIN teacher_discipline_classrooms tdc ON tdc.id = lessons_board_lesson_weekdays.teacher_discipline_classroom_id')
      .joins('INNER JOIN disciplines d ON d.id = tdc.discipline_id')
      .where(classrooms: { id: classroom_id })
      .where('d.id IN (?)', discipline_ids)
      .where(tdc: { active: true })
      .where(tdc: { discarded_at: nil })
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
    query_discarded = filter_effective_archived_boards(query_discarded, archived_since)
    
    # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
    if @school_year.present?
      query_discarded = query_discarded.where(classrooms: { year: @school_year })
    end
    
    # Filtrar por período se fornecido
    if periods.present? && periods.any? { |p| p.present? }
      query_discarded = query_discarded.where('lb.period IN (?)', periods.compact)
    end
    
    weekdays_data_discarded = query_discarded
      .distinct
      .pluck('d.id', :weekday)
    
    weekdays_data_discarded.each do |discipline_id, weekday|
      discarded_result[discipline_id] ||= []
      discarded_result[discipline_id] << weekday unless discarded_result[discipline_id].include?(weekday)
    end
    
    # Para disciplinas que não foram encontradas OU que foram encontradas mas sem weekdays, tenta sem filtrar por período
    missing_discipline_ids = discipline_ids.select { |id| active_result[id].blank? }
    if missing_discipline_ids.any?
      # Não filtrar por teacher_id - buscar weekdays de todos os professores que têm a disciplina
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
      
      # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
      if @school_year.present?
        weekdays_data_fallback = weekdays_data_fallback.where(classrooms: { year: @school_year })
      end
      
      weekdays_data_fallback = weekdays_data_fallback.distinct.pluck('d.id', :weekday)
      
      weekdays_data_fallback.each do |discipline_id, weekday|
        active_result[discipline_id] ||= []
        active_result[discipline_id] << weekday unless active_result[discipline_id].include?(weekday)
      end
      
      # Buscar também quadros excluídos sem período (fallback)
      # Não filtrar por teacher_id - buscar weekdays de todos os professores que têm a disciplina
      weekdays_data_discarded_fallback = LessonsBoardLessonWeekday.unscoped
        .joins('INNER JOIN lessons_board_lessons lbl ON lbl.id = lessons_board_lesson_weekdays.lessons_board_lesson_id')
        .joins('INNER JOIN lessons_boards lb ON lb.id = lbl.lessons_board_id AND lb.discarded_at IS NOT NULL')
        .joins('INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id')
        .joins('INNER JOIN classrooms ON classrooms.id = cg.classroom_id')
        .joins('INNER JOIN teacher_discipline_classrooms tdc ON tdc.id = lessons_board_lesson_weekdays.teacher_discipline_classroom_id')
        .joins('INNER JOIN disciplines d ON d.id = tdc.discipline_id')
        .where(classrooms: { id: classroom_id })
        .where('d.id IN (?)', missing_discipline_ids)
        .where(tdc: { active: true })
        .where(tdc: { discarded_at: nil })
        .where.not(weekday: nil)
        .where.not(teacher_discipline_classroom_id: nil)
      weekdays_data_discarded_fallback = filter_effective_archived_boards(weekdays_data_discarded_fallback, archived_since)
      
      # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
      if @school_year.present?
        weekdays_data_discarded_fallback = weekdays_data_discarded_fallback.where(classrooms: { year: @school_year })
      end
      
      weekdays_data_discarded_fallback = weekdays_data_discarded_fallback.distinct.pluck('d.id', :weekday)
            
      weekdays_data_discarded_fallback.each do |discipline_id, weekday|
        discarded_result[discipline_id] ||= []
        discarded_result[discipline_id] << weekday unless discarded_result[discipline_id].include?(weekday)
      end
    end
    
    # Buscar também quadros excluídos para todas as disciplinas, mesmo que tenham sido encontradas no ativo
    # Isso garante que encontramos todos os quadros excluídos, independente do período
    # Não filtrar por teacher_id - buscar weekdays de todos os professores que têm a disciplina
    weekdays_data_discarded_all = LessonsBoardLessonWeekday.unscoped
      .joins('INNER JOIN lessons_board_lessons lbl ON lbl.id = lessons_board_lesson_weekdays.lessons_board_lesson_id')
      .joins('INNER JOIN lessons_boards lb ON lb.id = lbl.lessons_board_id AND lb.discarded_at IS NOT NULL')
      .joins('INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id')
      .joins('INNER JOIN classrooms ON classrooms.id = cg.classroom_id')
      .joins('INNER JOIN teacher_discipline_classrooms tdc ON tdc.id = lessons_board_lesson_weekdays.teacher_discipline_classroom_id')
      .joins('INNER JOIN disciplines d ON d.id = tdc.discipline_id')
      .where(classrooms: { id: classroom_id })
      .where('d.id IN (?)', discipline_ids)
      .where(tdc: { active: true })
      .where(tdc: { discarded_at: nil })
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
    weekdays_data_discarded_all = filter_effective_archived_boards(weekdays_data_discarded_all, archived_since)
    
    # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
    if @school_year.present?
      weekdays_data_discarded_all = weekdays_data_discarded_all.where(classrooms: { year: @school_year })
    end
    
    weekdays_data_discarded_all = weekdays_data_discarded_all.distinct.pluck('d.id', :weekday)
        
    weekdays_data_discarded_all.each do |discipline_id, weekday|
      discarded_result[discipline_id] ||= []
      discarded_result[discipline_id] << weekday unless discarded_result[discipline_id].include?(weekday)
    end
        
    [active_result, discarded_result]
  end

  def get_discipline_weekdays(classroom_id, discipline_id, period)
    # Método mantido para compatibilidade, mas agora usa o método otimizado
    all_weekdays, _discarded_weekdays = get_all_disciplines_weekdays(classroom_id, [discipline_id], [period])
    all_weekdays[discipline_id] || []
  end

  def get_knowledge_areas_weekdays(classroom_id, knowledge_area_ids, periods, teacher_id = nil)
    # Buscar weekdays para áreas de conhecimento através das disciplinas que pertencem a essas áreas
    # Retorna dois hashes: [active_weekdays, discarded_weekdays]
    # active_weekdays: { knowledge_area_id => [weekdays] } - quadros ativos
    # discarded_weekdays: { knowledge_area_id => [weekdays] } - quadros excluídos
    # Se teacher_id for fornecido, filtra apenas as disciplinas desse professor na turma
    # IMPORTANTE: Os weekdays não são filtrados por teacher_id para garantir que se dois professores
    # têm a mesma disciplina, ambos vejam os mesmos dias pendentes
    
    active_result = {}
    discarded_result = {}
    return [active_result, discarded_result] if knowledge_area_ids.blank?
    
    # Buscar disciplinas que pertencem às áreas de conhecimento
    # Se teacher_id for fornecido, filtrar apenas disciplinas desse professor na turma
    if teacher_id.present?
      # Buscar disciplinas do professor através de teacher_discipline_classroom
      discipline_ids = TeacherDisciplineClassroom
        .where(classroom_id: classroom_id)
        .where(teacher_id: teacher_id)
        .where(active: true)
        .where(discarded_at: nil)
        .joins(:discipline)
        .where(disciplines: { knowledge_area_id: knowledge_area_ids })
        .pluck(:discipline_id)
        .uniq
    else
      # Se não houver teacher_id, buscar todas as disciplinas das áreas de conhecimento
      discipline_ids = Discipline.where(knowledge_area_id: knowledge_area_ids)
                                 .pluck(:id)
    end
    
    return [active_result, discarded_result] if discipline_ids.blank?
    
    # Buscar weekdays das disciplinas (ativos e excluídos)
    # Passar teacher_id para filtrar apenas os weekdays do professor específico
    all_weekdays, discarded_weekdays = get_all_disciplines_weekdays(classroom_id, discipline_ids, periods || [], teacher_id)
    
    # Agrupar weekdays por área de conhecimento
    knowledge_area_ids.each do |knowledge_area_id|
      # Buscar disciplinas desta área de conhecimento
      # Discipline tem belongs_to :knowledge_area, então buscar diretamente por knowledge_area_id
      ka_discipline_ids = Discipline.where(knowledge_area_id: knowledge_area_id)
                                    .pluck(:id)
      
      # Coletar todos os weekdays das disciplinas desta área (ativos e excluídos)
      active_weekdays = []
      discarded_weekdays_ka = []
      ka_discipline_ids.each do |discipline_id|
        active_weekdays.concat(all_weekdays[discipline_id] || [])
        discarded_weekdays_ka.concat(discarded_weekdays[discipline_id] || [])
      end
      
      active_result[knowledge_area_id] = active_weekdays.uniq
      discarded_result[knowledge_area_id] = discarded_weekdays_ka.uniq
    end
    
    [active_result, discarded_result]
  end

  def get_teacher_weekdays(classroom_id, teacher_ids, periods)
    # Buscar todos os weekdays de todos os professores na turma
    # Retorna um array único de weekdays: ['monday', 'tuesday', etc]
    
    result = []
    
    # Primeiro tenta com período específico
    weekdays_query = LessonsBoardLessonWeekday
      .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
      .joins(:teacher_discipline_classroom)
      .where(classrooms: { id: classroom_id })
      .where(lessons_boards: { period: periods })
      .where(teacher_discipline_classrooms: { teacher_id: teacher_ids })
      .where(teacher_discipline_classrooms: { active: true })
      .where(teacher_discipline_classrooms: { discarded_at: nil })
      .where.not(weekday: nil)
      .where.not(teacher_discipline_classroom_id: nil)
    
    # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
    if @school_year.present?
      weekdays_query = weekdays_query.where(classrooms: { year: @school_year })
    end
    
    weekdays_data = weekdays_query.distinct.pluck(:weekday)
    result.concat(weekdays_data)
    
    # Se não encontrou nada, tenta sem filtrar por período
    if result.empty?
      weekdays_query_fallback = LessonsBoardLessonWeekday
        .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
        .joins(:teacher_discipline_classroom)
        .where(classrooms: { id: classroom_id })
        .where(teacher_discipline_classrooms: { teacher_id: teacher_ids })
        .where(teacher_discipline_classrooms: { active: true })
        .where(teacher_discipline_classrooms: { discarded_at: nil })
        .where.not(weekday: nil)
        .where.not(teacher_discipline_classroom_id: nil)
      
      # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
      if @school_year.present?
        weekdays_query_fallback = weekdays_query_fallback.where(classrooms: { year: @school_year })
      end
      
      weekdays_data_fallback = weekdays_query_fallback.distinct.pluck(:weekday)
      result.concat(weekdays_data_fallback)
    end
    
    result.uniq
  end

  def get_week_number(date)
    # Retorna um identificador único para a semana da data (ISO 8601: segunda-feira como início)
    # Formato: [ano, número_da_semana]
    date = date.to_date
    
    # cweek retorna o número da semana ISO 8601 (segunda-feira como início)
    # cwyear retorna o ano da semana ISO 8601
    week_number = [date.cwyear, date.cweek]
    
    week_number
  end

  # discarded_at do último quadro arquivado da turma (data de troca do quadro).
  # Ignora quadros "excluídos" (discarded_at anterior ao início do calendário).
  def lessons_board_archive_date(classroom_id)
    @lessons_board_archive_dates ||= {}
    return @lessons_board_archive_dates[classroom_id] if @lessons_board_archive_dates.key?(classroom_id)

    query = LessonsBoard.unscoped
      .joins(classrooms_grade: :classroom)
      .where(classrooms_grades: { classroom_id: classroom_id })
      .where.not(discarded_at: nil)

    query = query.where(classrooms: { year: @school_year }) if @school_year.present?

    archived_since = effective_archived_since(classroom_id)
    query = query.where('lessons_boards.discarded_at >= ?', archived_since) if archived_since

    @lessons_board_archive_dates[classroom_id] = query.maximum(:discarded_at)&.to_date
  end

  def effective_archived_since(classroom_id)
    @effective_archived_since ||= {}
    return @effective_archived_since[classroom_id] if @effective_archived_since.key?(classroom_id)

    classroom = Classroom.find_by(id: classroom_id)
    unless classroom
      @effective_archived_since[classroom_id] = nil
      return nil
    end

    year = @school_year.presence || classroom.year
    calendar = CurrentSchoolCalendarFetcher.new(classroom.unity, classroom, year).fetch
    @effective_archived_since[classroom_id] = calendar&.first_day&.to_date&.beginning_of_day
  rescue StandardError
    @effective_archived_since[classroom_id] = nil
  end

  def filter_effective_archived_boards(relation, archived_since)
    return relation if archived_since.blank?

    relation.where('lb.discarded_at >= ?', archived_since)
  end

  # Regra: date <= archive_date (até quando funcionou) => arquivado; date > archive_date => ativo.
  def school_days_by_board_archive_date(all_school_days, active_weekdays, archived_weekdays, archive_date)
    all_school_days.select do |date|
      wd = get_equivalent_weekday_number(date)
      numbers = if archive_date && date <= archive_date
                  archived_weekdays.presence || active_weekdays
                else
                  active_weekdays.presence || archived_weekdays
                end
      numbers.include?(wd)
    end
  end

  def has_record_in_same_week_from_discarded_board?(pending_date, loaded_discarded_dates, school_days_discarded, classroom, discipline, is_general_frequency, today, discarded_weekday_numbers)
    # Verifica se há registro na mesma semana que esteja em um dia de quadro excluído
    # IMPORTANTE: Só retorna true se realmente houver um registro em um quadro excluído na mesma semana
    # e esse registro esteja compensando especificamente essa pendência
    # GARANTE que está verificando na mesma turma e disciplina
    return false if discarded_weekday_numbers.blank?
    
    pending_week = get_week_number(pending_date)
    
    # Primeiro verificar nos registros já carregados (que já foram identificados como estando em quadros excluídos)
    # Esses registros já foram filtrados por turma e disciplina antes de serem passados aqui
    has_discarded_in_same_week = loaded_discarded_dates.any? do |discarded_date|
      discarded_week = get_week_number(discarded_date)
      discarded_week == pending_week
    end
    
    # Se não encontrou nos registros já carregados, verificar diretamente no banco
    # Mas apenas se realmente houver weekdays descartados para verificar
    # IMPORTANTE: Sempre filtrar por turma e disciplina para garantir que está verificando o registro correto
    if !has_discarded_in_same_week && discarded_weekday_numbers.any?
      week_start = pending_date.beginning_of_week(:monday)
      week_end = pending_date.end_of_week(:monday)
      
      # Buscar registros na mesma semana que estejam em dias de quadro excluído
      # GARANTIR que está filtrando por turma e disciplina corretamente
      week_records = if is_general_frequency
        DailyFrequency
          .by_classroom_id(classroom.id)  # Filtrar por turma
          .general_frequency  # Frequência geral (sem disciplina específica)
          .where('frequency_date >= ? AND frequency_date <= ?', week_start, week_end)
          .where('frequency_date <= ?', today)
          .pluck(:frequency_date)
          .map(&:to_date)
      else
        DailyFrequency
          .by_classroom_id(classroom.id)  # Filtrar por turma
          .where(discipline_id: discipline.id)  # Filtrar por disciplina
          .where('frequency_date >= ? AND frequency_date <= ?', week_start, week_end)
          .where('frequency_date <= ?', today)
          .pluck(:frequency_date)
          .map(&:to_date)
      end
      
      # Verificar se algum registro da semana está em um dia de quadro excluído
      # E está na mesma semana da pendência
      # Os registros já foram filtrados por turma e disciplina acima
      has_discarded_in_same_week = week_records.any? do |record_date|
        record_week = get_week_number(record_date)
        # Verificar se o dia da semana do registro está nos weekdays descartados
        # IMPORTANTE: Para sábados mapeados, usar o dia equivalente ao invés do próprio sábado
        is_in_discarded = discarded_weekday_numbers.include?(get_equivalent_weekday_number(record_date))
        record_week == pending_week && is_in_discarded
      end
    end
    
    has_discarded_in_same_week
  end

  def has_content_record_in_same_week_from_discarded_board?(pending_date, loaded_discarded_dates, school_days_discarded, classroom, discipline, today, discarded_weekday_numbers)
    # Verifica se há registro de conteúdo na mesma semana que esteja em um dia de quadro excluído
    # Primeiro verifica nos registros já carregados, depois busca diretamente no banco se necessário
    # GARANTE que está verificando na mesma turma e disciplina
    return false if discarded_weekday_numbers.blank?
    
    pending_week = get_week_number(pending_date)
    
    # Primeiro verificar nos registros já carregados (que já foram identificados como estando em quadros excluídos)
    # Esses registros já foram filtrados por turma e disciplina antes de serem passados aqui
    has_discarded_in_same_week = loaded_discarded_dates.any? do |discarded_date|
      discarded_week = get_week_number(discarded_date)
      discarded_week == pending_week
    end
    
    # Se não encontrou, verificar diretamente no banco se existe registro na mesma semana
    # IMPORTANTE: Sempre filtrar por turma e disciplina para garantir que está verificando o registro correto
    if !has_discarded_in_same_week && discarded_weekday_numbers.any?
      week_start = pending_date.beginning_of_week(:monday)
      week_end = pending_date.end_of_week(:monday)
      
      # Buscar registros de conteúdo na mesma semana
      # GARANTIR que está filtrando por turma e disciplina corretamente
      week_records = DisciplineContentRecord
        .joins(:content_record)
        .where(content_records: { classroom_id: classroom.id })  # Filtrar por turma
        .where(discipline_id: discipline.id)  # Filtrar por disciplina
        .where('content_records.record_date >= ? AND content_records.record_date <= ?', week_start, week_end)
        .where('content_records.record_date <= ?', today)
        .pluck('content_records.record_date')
        .map(&:to_date)
      
      # Verificar se algum registro da semana está em um dia de quadro excluído
      # Verificar diretamente pelo dia da semana (wday) ao invés de verificar se está em school_days_discarded
      # porque school_days_discarded só inclui dias letivos no range, e o registro pode estar fora
      has_discarded_in_same_week = week_records.any? do |record_date|
        record_week = get_week_number(record_date)
        # Verificar se o dia da semana do registro está nos weekdays descartados
        # IMPORTANTE: Para sábados mapeados, usar o dia equivalente ao invés do próprio sábado
        is_in_discarded = discarded_weekday_numbers.include?(get_equivalent_weekday_number(record_date))
        if record_week == pending_week && is_in_discarded
          true
        else
          false
        end
      end
    end
    
    has_discarded_in_same_week
  end

  def has_knowledge_area_content_record_in_same_week_from_discarded_board?(pending_date, loaded_discarded_dates, school_days_discarded, classroom, knowledge_area_id, today, discarded_weekday_numbers)
    # Verifica se há registro de conteúdo de área de conhecimento na mesma semana que esteja em um dia de quadro excluído
    # Primeiro verifica nos registros já carregados, depois busca diretamente no banco se necessário
    # GARANTE que está verificando na mesma turma e área de conhecimento
    return false if discarded_weekday_numbers.blank?
    
    pending_week = get_week_number(pending_date)
    
    # Primeiro verificar nos registros já carregados (que já foram identificados como estando em quadros excluídos)
    # Esses registros já foram filtrados por turma e área de conhecimento antes de serem passados aqui
    has_discarded_in_same_week = loaded_discarded_dates.any? do |discarded_date|
      discarded_week = get_week_number(discarded_date)
      discarded_week == pending_week
    end
    
    # Se não encontrou, verificar diretamente no banco se existe registro na mesma semana
    # IMPORTANTE: Sempre filtrar por turma e área de conhecimento para garantir que está verificando o registro correto
    if !has_discarded_in_same_week && discarded_weekday_numbers.any?
      week_start = pending_date.beginning_of_week(:monday)
      week_end = pending_date.end_of_week(:monday)
      
      # Buscar registros de conteúdo de área de conhecimento na mesma semana
      # GARANTIR que está filtrando por turma e área de conhecimento corretamente
      week_records = KnowledgeAreaContentRecord
        .joins(:content_record)
        .joins(:knowledge_areas)
        .where(content_records: { classroom_id: classroom.id })  # Filtrar por turma
        .where(knowledge_areas: { id: knowledge_area_id })  # Filtrar por área de conhecimento
        .where('content_records.record_date >= ? AND content_records.record_date <= ?', week_start, week_end)
        .where('content_records.record_date <= ?', today)
        .pluck('content_records.record_date')
        .map(&:to_date)
      
      # Verificar se algum registro da semana está em um dia de quadro excluído
      # Verificar diretamente pelo dia da semana (wday) ao invés de verificar se está em school_days_discarded
      # porque school_days_discarded só inclui dias letivos no range, e o registro pode estar fora
      has_discarded_in_same_week = week_records.any? do |record_date|
        record_week = get_week_number(record_date)
        # Verificar se o dia da semana do registro está nos weekdays descartados
        # IMPORTANTE: Para sábados mapeados, usar o dia equivalente ao invés do próprio sábado
        is_in_discarded = discarded_weekday_numbers.include?(get_equivalent_weekday_number(record_date))
        if record_week == pending_week && is_in_discarded
          true
        else
          false
        end
      end
    end
    
    has_discarded_in_same_week
  end

  def has_discipline_content_record_on_date?(classroom, discipline_ids, date, today)
    # Verifica se há registro de conteúdo por disciplina na data especificada
    # Para turmas infantis onde o professor iniciou preenchimento por disciplina
    return false if date > today
    return false if discipline_ids.blank?
    
    DisciplineContentRecord
      .joins(:content_record)
      .where(content_records: { classroom_id: classroom.id })
      .where(discipline_id: discipline_ids)
      .where('content_records.record_date = ?', date)
      .exists?
  end

  INFANTIL_GRADE_PATTERN = /creche|pre|pre i|pre ii|pre[- ]escola(r)?|maternal|bercario|jardim|infantil|aee/
  INFANTIL_COURSE_PATTERN = /infantil|aee/

  def is_infantil_classroom?(classroom)
    classroom.classrooms_grades.any? do |classroom_grade|
      infantil_grade?(classroom_grade.grade)
    end
  end

  def multigrade_infantil_fundamental_classroom?(classroom)
    return false if classroom.blank?

    has_infantil = false
    has_non_infantil = false

    classroom.classrooms_grades.each do |classroom_grade|
      if infantil_grade?(classroom_grade.grade)
        has_infantil = true
      else
        has_non_infantil = true
      end
    end

    has_infantil && has_non_infantil
  end

  def infantil_grade_ids(classroom)
    return [] if classroom.blank?

    classroom.classrooms_grades.select do |classroom_grade|
      infantil_grade?(classroom_grade.grade)
    end.map(&:grade_id)
  end

  def non_infantil_grade_ids(classroom)
    return [] if classroom.blank?

    classroom.classrooms_grades.reject do |classroom_grade|
      infantil_grade?(classroom_grade.grade)
    end.map(&:grade_id)
  end

  def infantil_knowledge_area_ids_for_classroom(classroom, teacher_id)
    infantil_discipline_ids = discipline_ids_for_grade_ids(classroom, infantil_grade_ids(classroom), teacher_id)
    return [] if infantil_discipline_ids.blank?

    KnowledgeArea.joins(:disciplines)
                 .where(disciplines: { id: infantil_discipline_ids })
                 .distinct
                 .pluck(:id)
  end

  def infantil_knowledge_area_param?(classroom, teacher_id, param_id)
    return false if param_id.blank? || classroom.blank? || teacher_id.blank?

    infantil_knowledge_area_ids_for_classroom(classroom, teacher_id).map(&:to_s).include?(param_id.to_s)
  end

  def discipline_ids_for_grade_ids(classroom, grade_ids, teacher_id)
    return [] if classroom.blank? || grade_ids.blank? || teacher_id.blank?

    TeacherDisciplineClassroom
      .by_teacher_id(teacher_id)
      .by_classroom(classroom)
      .by_year(@school_year)
      .where(grade_id: grade_ids)
      .pluck(:discipline_id)
      .uniq
  end

  def infantil_grade?(grade)
    return false if grade.blank?
    return true if infantil_course_description?(grade.course&.description)
    return true if infantil_grade_description?(grade.description)    

    false
  end

  def infantil_grade_description?(description)
    return false if description.blank?

    I18n.transliterate(description.to_s.downcase).match?(INFANTIL_GRADE_PATTERN)
  end

  def infantil_course_description?(description)
    return false if description.blank?

    I18n.transliterate(description.to_s.downcase).match?(INFANTIL_COURSE_PATTERN)
  end

  def add_saturdays_from_lesson_boards(all_school_days, start_date, end_date, classroom_id)
    sabados_letivos_map = saturdays_mapping.mapping

    return all_school_days if sabados_letivos_map.blank?
    
    # Buscar todos os sábados no intervalo de datas
    saturdays_in_range = start_date.upto(end_date).select { |date| date.saturday? }
    
    # Para cada sábado, verificar se está mapeado e se o dia equivalente está no quadro de aulas
    saturdays_to_add = []
    saturdays_in_range.each do |saturday_date|
      # Verificar se o sábado está mapeado no arquivo de configuração
      date_key = saturday_date.strftime("%Y-%m-%d")
      equivalent_weekday = sabados_letivos_map[date_key]
      
      next if equivalent_weekday.blank?
      
      # Verificar se o dia equivalente está no quadro de aulas para esta turma
      has_equivalent_weekday = LessonsBoardLessonWeekday
        .joins(lessons_board_lesson: [lessons_board: [classrooms_grade: :classroom]])
        .joins(:teacher_discipline_classroom)
        .where(classrooms: { id: classroom_id })
        .where(teacher_discipline_classrooms: { active: true })
        .where(teacher_discipline_classrooms: { discarded_at: nil })
        .where('lessons_boards.discarded_at IS NULL')
        .where(weekday: equivalent_weekday)
      
      # IMPORTANTE: Filtrar por ano do quadro de aulas para garantir que está buscando do ano correto
      if @school_year.present?
        has_equivalent_weekday = has_equivalent_weekday.where(classrooms: { year: @school_year })
      end
      
      # Se o dia equivalente estiver no quadro de aulas, adicionar o sábado
      if has_equivalent_weekday.exists?
        saturdays_to_add << saturday_date unless all_school_days.include?(saturday_date)
      end
    end
    
    # Retornar a lista atualizada com os sábados adicionados
    (all_school_days + saturdays_to_add).sort
  end

  def saturdays_mapping
    @saturdays_mapping ||= SchoolSaturdaysMapping.new(school_calendar: @current_school_calendar)
  end

  def get_equivalent_weekday_number(date)
    saturdays_mapping.weekday_number_for(date)
  end

  def filter_saturdays_by_events(pending_dates, classroom, school_calendar)
    # Filtra sábados pendentes baseado em eventos cadastrados
    # Se um sábado não tiver evento cadastrado ou o evento não se aplicar à turma, remove da lista
    return pending_dates if pending_dates.blank? || school_calendar.blank?
    
    # Obter IDs dos cursos da turma
    classroom_course_ids = classroom.courses.map(&:id)
    
    pending_dates.reject do |date|
      # Só processar sábados
      next false unless date.saturday?
      
      # Buscar eventos cadastrados para esta data
      events = school_calendar.events.by_date(date)
      
      # Se não houver eventos, remover o sábado da lista de pendentes
      next true if events.blank?
      
      # Verificar se algum evento se aplica à turma
      has_applicable_event = events.any? do |event|
        # Se o evento for geral (by_unity), verificar se a turma é da mesma unidade
        if event.coverage_by_unity?
          event.unity_id == classroom.unity_id
        # Se o evento for por curso e a turma for do mesmo curso, aplicar
        elsif event.coverage_by_course? && event.course_id.present?
          classroom_course_ids.include?(event.course_id)
        # Se o evento for por grade e a turma tiver o mesmo grade, aplicar
        elsif event.coverage_by_grade? && event.grade_id.present?
          classroom.grade_ids.include?(event.grade_id)
        # Se o evento for por turma e for a mesma turma, aplicar
        elsif event.coverage_by_classroom? && event.classroom_id.present?
          classroom.id == event.classroom_id
        else
          false
        end
      end
      
      # Se não houver evento aplicável, remover da lista
      !has_applicable_event
    end
  end

  def process_infantil_classroom(classroom, knowledge_area_ids, school_calendar, start_date, end_date, is_general_frequency, all_school_days, today, grade_id, teacher_id)
    results = []
    
    return results if knowledge_area_ids.blank?

    teacher = Teacher.find_by(id: teacher_id)
    return results unless teacher

    # Para turmas infantis, verificar se há quadro de aulas para áreas de conhecimento
    # Se não houver weekdays no quadro de aulas, não há pendências
    # Buscar weekdays para áreas de conhecimento (se houver quadro de aulas)
    # IMPORTANTE: Passar teacher_id para filtrar apenas os weekdays do professor específico
    knowledge_area_weekdays, knowledge_area_discarded_weekdays = get_knowledge_areas_weekdays(classroom.id, knowledge_area_ids, nil, teacher_id)

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

    # Verificar se o professor iniciou preenchimento por disciplina
    # Se sim, também verificar registros por disciplina ao invés de apenas por área de conhecimento
    started_as_discipline = DisciplineContentRecord
      .by_teacher_id(teacher_id)
      .by_classroom_id(classroom.id)
      .exists?
    
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
    
    # Se o professor iniciou preenchimento por disciplina, buscar também registros por disciplina
    # Buscar disciplinas que pertencem às áreas de conhecimento
    discipline_ids_by_knowledge_area = {}
    all_contents_by_discipline = {}
    if started_as_discipline
      knowledge_area_ids.each do |knowledge_area_id|
        discipline_ids = Discipline.where(knowledge_area_id: knowledge_area_id)
                                   .not_grouper
                                   .not_descriptor
                                   .pluck(:id)
        discipline_ids_by_knowledge_area[knowledge_area_id] = discipline_ids
      end
      
      # Buscar conteúdos por disciplina em batch
      all_discipline_ids = discipline_ids_by_knowledge_area.values.flatten.uniq
      if all_discipline_ids.any?
        discipline_content_data = DisciplineContentRecord
          .joins(:content_record)
          .where(content_records: { classroom_id: classroom.id })
          .where(discipline_id: all_discipline_ids)
          .where('content_records.record_date >= ? AND content_records.record_date <= ? AND content_records.record_date <= ?', start_date, end_date, today)
          .pluck(:discipline_id, 'content_records.record_date')
        
        all_contents_by_discipline = discipline_content_data
          .group_by { |d| d[0] }
          .transform_values { |dates| dates.map { |d| d[1].to_date }.to_set }
      end
    end

    # Processar cada área de conhecimento
    knowledge_area_ids.each do |knowledge_area_id|
      knowledge_area = KnowledgeArea.find_by(id: knowledge_area_id)
      next unless knowledge_area

      # Verificar se a área de conhecimento tem weekdays no quadro de aulas
      # Se não houver weekdays, não há pendências
      area_weekdays = knowledge_area_weekdays[knowledge_area_id] || []
      area_discarded_weekdays = knowledge_area_discarded_weekdays[knowledge_area_id] || []

      # Mapear weekdays excluídos para números (sempre necessário para quadros descartados)
      discarded_weekday_numbers = area_discarded_weekdays.map do |wd|
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
      
      if area_weekdays.empty? && area_discarded_weekdays.empty?
        school_days_for_content = []
        school_days_for_frequency = []
      else
        weekday_numbers = area_weekdays.map do |wd|
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

        # data <= arquivamento (até quando funcionou) => arquivado; depois => ativo
        archive_date = lessons_board_archive_date(classroom.id)
        school_days_for_content = school_days_by_board_archive_date(
          all_school_days, weekday_numbers, discarded_weekday_numbers, archive_date
        )
        school_days_for_frequency = is_general_frequency ? school_days_for_content : []
      end
      
      # Obter dias que estão em quadros excluídos
      # IMPORTANTE: Para sábados mapeados, usar o dia equivalente ao invés do próprio sábado
      school_days_discarded = all_school_days.select { |date| discarded_weekday_numbers.include?(get_equivalent_weekday_number(date)) }
      optional_holiday_makeup_dates = Set.new

      # Obter frequências registradas
      if @count_only
        if is_general_frequency
          frequency_dates_set = general_freq_dates
        else
          frequency_dates_set = Set.new # Turmas infantis geralmente usam frequência geral
        end

        content_dates_set = all_contents_by_knowledge_area[knowledge_area_id] || Set.new
        
        # Se o professor iniciou preenchimento por disciplina, também verificar registros por disciplina
        if started_as_discipline
          discipline_ids = discipline_ids_by_knowledge_area[knowledge_area_id] || []
          discipline_content_dates = Set.new
          discipline_ids.each do |discipline_id|
            discipline_content_dates.merge(all_contents_by_discipline[discipline_id] || Set.new)
          end
          # Combinar datas de área de conhecimento e disciplina
          content_dates_set = content_dates_set + discipline_content_dates
        end

        # Calcular pendências baseado apenas no quadro ativo
        pending_frequency_dates = school_days_for_frequency.select { |date| date <= today && !frequency_dates_set.include?(date) }.to_a
        pending_content_dates = school_days_for_content.select { |date| date <= today && !content_dates_set.include?(date) }.to_a
        
        # Incluir registros que estão em dias de quadro excluído, mesmo que também estejam no quadro ativo
        frequency_dates_in_discarded = frequency_dates_set.select { |date| school_days_discarded.include?(date) }
        
        # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
        removed_frequency_count = 0
        pending_frequency_dates.reject! do |pending_date|
          pending_week = get_week_number(pending_date)
          has_discarded_in_same_week = frequency_dates_in_discarded.any? do |discarded_date|
            discarded_week = get_week_number(discarded_date)
            if discarded_week == pending_week
              true
            else
              false
            end
          end
          if has_discarded_in_same_week
            removed_frequency_count += 1
          end
          has_discarded_in_same_week
        end
        
        content_dates_in_discarded = content_dates_set.select { |date| school_days_discarded.include?(date) && !school_days_for_content.include?(date) }
        
        # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
        removed_content_count = 0
        pending_content_dates.reject! do |pending_date|
          has_discarded_in_same_week = has_knowledge_area_content_record_in_same_week_from_discarded_board?(
            pending_date, 
            content_dates_in_discarded.to_a, 
            school_days_discarded, 
            classroom, 
            knowledge_area_id, 
            today,
            discarded_weekday_numbers
          )
          if has_discarded_in_same_week
            pending_week = get_week_number(pending_date)
            # Removendo pendência de conteúdo (área)
            removed_content_count += 1
          end
          has_discarded_in_same_week
        end
        
        # Filtrar sábados pendentes baseado em eventos cadastrados
        pending_frequency_dates = filter_saturdays_by_events(pending_frequency_dates, classroom, school_calendar)
        pending_content_dates = filter_saturdays_by_events(pending_content_dates, classroom, school_calendar)
        optional_holiday_makeup_dates = apply_optional_holidays!(
          pending_frequency_dates, pending_content_dates,
          classroom, classroom.period, start_date, end_date, today,
          frequency_dates_set: frequency_dates_set,
          content_dates_set: content_dates_set
        )
        
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
        
        # Se o professor iniciou preenchimento por disciplina, também buscar registros por disciplina
        if started_as_discipline
          discipline_ids = discipline_ids_by_knowledge_area[knowledge_area_id] || []
          if discipline_ids.any?
            discipline_content_records = DisciplineContentRecord
              .joins(:content_record)
              .where(content_records: { classroom_id: classroom.id })
              .where(discipline_id: discipline_ids)
              .where('content_records.record_date >= ? AND content_records.record_date <= ?', start_date, end_date)
              .pluck('content_records.record_date')
              .map(&:to_date)
            # Combinar datas de área de conhecimento e disciplina
            content_records = (content_records + discipline_content_records).uniq
          end
        end

        # Calcular dias pendentes baseado apenas no quadro ativo
        pending_frequency_dates = (school_days_for_frequency - frequencies).select { |date| date <= today }
        pending_content_dates = (school_days_for_content - content_records).select { |date| date <= today }
        
        # Identificar registros em datas de quadro excluído
        frequency_dates_in_discarded = frequencies.select { |date| school_days_discarded.include?(date) && !school_days_for_frequency.include?(date) }
        
        # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
        removed_frequency_count = 0
        pending_frequency_dates.reject! do |pending_date|
          pending_week = get_week_number(pending_date)
          has_discarded_in_same_week = frequency_dates_in_discarded.any? do |discarded_date|
            discarded_week = get_week_number(discarded_date)
            if discarded_week == pending_week
              true
            else
              false
            end
          end
          if has_discarded_in_same_week
            removed_frequency_count += 1
          end
          has_discarded_in_same_week
        end
        
        content_dates_in_discarded = content_records.select { |date| school_days_discarded.include?(date) && !school_days_for_content.include?(date) }
        
        # Para cada data pendente do quadro ativo, verificar se há registro do quadro excluído na mesma semana
        removed_content_count = 0
        pending_content_dates.reject! do |pending_date|
          pending_week = get_week_number(pending_date)
          has_discarded_in_same_week = content_dates_in_discarded.any? do |discarded_date|
            discarded_week = get_week_number(discarded_date)
            if discarded_week == pending_week
              true
            else
              false
            end
          end
          if has_discarded_in_same_week
            removed_content_count += 1
          end
          has_discarded_in_same_week
        end
        
        # Filtrar sábados pendentes baseado em eventos cadastrados
        pending_frequency_dates = filter_saturdays_by_events(pending_frequency_dates, classroom, school_calendar)
        pending_content_dates = filter_saturdays_by_events(pending_content_dates, classroom, school_calendar)
        optional_holiday_makeup_dates = apply_optional_holidays!(
          pending_frequency_dates, pending_content_dates,
          classroom, classroom.period, start_date, end_date, today,
          frequency_dates_set: frequencies,
          content_dates_set: content_records
        )
        
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
        in_lessons_board: area_weekdays.any?,
        pending_frequency_count: pending_frequency_count,
        pending_content_count: pending_content_count
      }
      
      if !@count_only || @include_dates
        result[:pending_frequency_dates] = pending_frequency_dates.sort
        # Se o professor iniciou preenchimento por disciplina, verificar se há registro por disciplina nas datas pendentes
        if started_as_discipline
          discipline_ids = discipline_ids_by_knowledge_area[knowledge_area_id] || []
          result[:pending_content_dates] = pending_content_dates.reject do |date|
            has_discipline_content_record_on_date?(classroom, discipline_ids, date, today)
          end.sort
        else
          result[:pending_content_dates] = pending_content_dates.sort
        end
        result[:optional_holiday_makeup_dates] = optional_holiday_makeup_dates.to_a
      end
      
      results << result
    end

    results
  end
end

