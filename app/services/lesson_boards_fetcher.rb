class LessonBoardsFetcher
  def initialize(user)
    @user = user
  end

  def lesson_boards(archived: false)
    scope = archived ? LessonsBoard.with_discarded.discarded : LessonsBoard
    @lesson_boards = scope.by_unity(unities).by_year(@user.current_school_year)
    @lesson_boards = @lesson_boards.joins(classrooms_grade: :classroom).order('classrooms.description')
    @lesson_boards = exclude_purged_boards(@lesson_boards) if archived
    @lesson_boards
  end

  def unities
    if @user.current_user_role.try(:role_administrator?)
      Unity.joins(:school_calendars)
           .where(school_calendars: { year: @user.current_school_year })
           .ordered
    else
      lessons_unities = []
      roles_ids = Role.where(access_level: AccessLevel::EMPLOYEE).pluck(:id)
      unities_user = UserRole.where(user_id: @user.id, role_id: roles_ids).pluck(:unity_id)
      LessonsBoard.by_unity(unities_user).each { |lesson_board| lessons_unities << lesson_board.classroom.unity.id }
      Unity.where(id: lessons_unities).ordered
    end
  end

  def by_classroom(classroom_id)
    LessonsBoard.joins(classrooms_grade: :classroom)
      .by_classroom(classroom_id)
      .by_year(@user.current_school_year)
  end

  def count_lessons(turma_id, disciplina_id, data)
    # Domingo não tem aulas no quadro de horários
    return 0 if data.sunday?

    if data.saturday?
      # Se for sábado, usa o dia da semana equivalente do arquivo de configuração
      total_aulas = count_lessons_by_saturday(turma_id, disciplina_id, data)
    else
      # Para segunda a sexta, usa o nome do dia da semana diretamente
      # Ruby strftime("%A") retorna: Monday, Tuesday, Wednesday, Thursday, Friday
      # Convertemos para minúsculas para corresponder ao formato do banco: monday, tuesday, etc.
      dia_semana_nome = data.strftime("%A").downcase

      # Valida se é um dia válido (segunda a sexta)
      dias_validos = %w[monday tuesday wednesday thursday friday]
      unless dias_validos.include?(dia_semana_nome)
        return 0
      end

      total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_semana_nome, true)
      if total_aulas == 0
        total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_semana_nome, false)
      end
    end

    total_aulas
  end

  def count_lessons_including_make_up(turma_id, disciplina_id, data)
    scheduled = count_lessons(turma_id, disciplina_id, data)
    return scheduled unless @user&.teacher_id.present?

    classroom = Classroom.find_by(id: turma_id)
    make_up = TeacherAbsence.make_up_lessons_count_for(
      classroom_id: turma_id,
      discipline_id: disciplina_id,
      teacher_id: @user.teacher_id,
      date: data,
      unity_id: classroom&.unity_id,
      count_lessons_on_date: ->(absence_date) { count_lessons(turma_id, disciplina_id, absence_date) }
    )

    scheduled + make_up
  end

  private

  def count_lessons_from_boards(turma_id, disciplina_id, dia_semana_nome, ativo)
    # Define filtro de ativo/inativo
    ativo_condicao = if ativo
      <<~SQL
        AND lb.discarded_at IS NULL
      SQL
    else
      calendar_start = calendar_first_day_sql(turma_id)
      purged_filter = if calendar_start
                        "AND lb.discarded_at >= '#{calendar_start}'"
                      else
                        ''
                      end
      <<~SQL
        AND lb.discarded_at IS NOT NULL
        #{purged_filter}
      SQL
    end

    sql = <<-SQL
      SELECT COALESCE(MAX(quadros.total_aulas), 0) AS total_aulas
      FROM (
        SELECT lb.id, COUNT(lbl.id) AS total_aulas
        FROM lessons_boards lb
        INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id
        INNER JOIN lessons_board_lessons lbl ON lbl.lessons_board_id = lb.id
        INNER JOIN lessons_board_lesson_weekdays lblw ON lblw.lessons_board_lesson_id = lbl.id
        INNER JOIN teacher_discipline_classrooms tdc ON tdc.classroom_id = cg.classroom_id
          AND tdc.id = lblw.teacher_discipline_classroom_id
          AND tdc.discipline_id = #{disciplina_id}
          AND tdc.discarded_at IS NULL
        WHERE cg.classroom_id = #{turma_id}
          AND lblw.weekday = '#{dia_semana_nome}'
          #{ativo_condicao}
        GROUP BY lb.id
      ) AS quadros
    SQL

    total_aulas = ActiveRecord::Base.connection.exec_query(sql).first&.dig("total_aulas") || 0
    total_aulas
  end

  def count_lessons_by_saturday(turma_id, disciplina_id, data)
    # Busca o dia da semana equivalente no cadastro de sábados letivos
    dia_equivalente = get_weekday_for_saturday(data, turma_id: turma_id)

    # Se não houver mapeamento configurado, retorna 0
    return 0 if dia_equivalente.blank?

    # Tenta quadros ativos
    total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_equivalente, true)
    if total_aulas == 0
      # Se não houver, tenta inativos
      total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_equivalente, false)
    end
    
    total_aulas
  end

  def get_weekday_for_saturday(date, turma_id: nil)
    school_calendar = school_calendar_for_classroom(turma_id, date)
    SchoolSaturdaysMapping.new(school_calendar: school_calendar).weekday_name_for(date)
  end

  def school_calendar_for_classroom(classroom_id, date)
    classroom = Classroom.find_by(id: classroom_id)
    return nil unless classroom

    CurrentSchoolCalendarFetcher.new(classroom.unity, classroom, date.year).fetch
  rescue StandardError
    SchoolCalendar.find_by(unity_id: classroom.unity_id, year: date.year)
  end

  def calendar_first_day_sql(classroom_id)
    classroom = Classroom.find_by(id: classroom_id)
    return nil unless classroom

    calendar = CurrentSchoolCalendarFetcher.new(classroom.unity, classroom, classroom.year).fetch
    calendar&.first_day&.to_date&.beginning_of_day
  rescue StandardError
    nil
  end

  # Quadros com discarded_at anterior ao início do calendário foram "excluídos"
  # logicamente e não devem aparecer na listagem de arquivados.
  def exclude_purged_boards(relation)
    relation
      .joins(<<-SQL.squish)
        INNER JOIN school_calendars sc
          ON sc.unity_id = classrooms.unity_id
         AND sc.year = classrooms.year
        INNER JOIN (
          SELECT school_calendar_id, MIN(start_at) AS first_day
          FROM school_calendar_steps
          GROUP BY school_calendar_id
        ) sc_start ON sc_start.school_calendar_id = sc.id
      SQL
      .where('lessons_boards.discarded_at >= sc_start.first_day')
  end

end
