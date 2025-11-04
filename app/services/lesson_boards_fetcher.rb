class LessonBoardsFetcher
  def initialize(user)
    @user = user
  end

  def lesson_boards
    @lesson_boards = LessonsBoard.by_unity(unities).by_year(@user.current_school_year)
    @lesson_boards.joins(classrooms_grade: :classroom).order('classrooms.description')
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
    if data.saturday?
      # se for sábado, chamar lógica especial
      total_aulas = count_lessons_by_saturday(turma_id, disciplina_id, data)
    else
      # Ruby wday: domingo=0..sábado=6 → banco: segunda=1..domingo=7
      # dia_semana = data.wday # numero do dia da semana
      dia_semana_nome = data.strftime("%A").downcase # nome do dia da semana

      total_aulas = ActiveRecord::Base.connection.exec_query(<<-SQL).first&.dig("total_aulas") || 0
        SELECT COUNT(lbl.id) AS total_aulas
        FROM lessons_boards lb
        INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id and cg.discarded_at IS NULL
        INNER JOIN lessons_board_lessons lbl
          ON lbl.lessons_board_id = lb.id
        INNER JOIN lessons_board_lesson_weekdays lblw
          ON lblw.lessons_board_lesson_id = lbl.id
        INNER JOIN teacher_discipline_classrooms tdc ON tdc.classroom_id = cg.classroom_id
          AND tdc.id = lblw.teacher_discipline_classroom_id
          AND tdc.discarded_at IS NULL
        WHERE cg.classroom_id = #{turma_id}
          AND lblw.weekday = '#{dia_semana_nome}'
          AND tdc.discipline_id = #{disciplina_id}
      SQL
    end

    total_aulas
  end

  private
  
  def count_lessons_by_saturday(turma_id, disciplina_id, data)
    # Conta quantos sábados letivos já ocorreram até o sábado informado
    sabados_letivos_anteriores = SchoolCalendarEvent
                                    .where(event_type: EventTypes::EXTRA_SCHOOL)
                                    .where("EXTRACT(DOW FROM start_date) = 6 OR EXTRACT(DOW FROM end_date) = 6")
                                    .where("start_date <= ?", data)
                                    .pluck(:start_date, :end_date)
                                    .flat_map { |start_date, end_date| (start_date..(end_date || start_date)).to_a.select(&:saturday?) }
                                    .uniq
                                    .count


    # Define qual dia da semana o sábado letivo "representa"
    dias_semana = %w[monday tuesday wednesday thursday friday]
    dia_equivalente = dias_semana[(sabados_letivos_anteriores - 1) % dias_semana.size]

    total_aulas = ActiveRecord::Base.connection.exec_query(<<-SQL).first&.dig("total_aulas") || 0
      SELECT COUNT(lbl.id) AS total_aulas
      FROM lessons_boards lb
      INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id AND cg.discarded_at IS NULL
      INNER JOIN lessons_board_lessons lbl ON lbl.lessons_board_id = lb.id
      INNER JOIN lessons_board_lesson_weekdays lblw ON lblw.lessons_board_lesson_id = lbl.id
      INNER JOIN teacher_discipline_classrooms tdc
        ON tdc.classroom_id = cg.classroom_id
        AND tdc.id = lblw.teacher_discipline_classroom_id
        AND tdc.discarded_at IS NULL
      WHERE cg.classroom_id = #{turma_id}
        AND lblw.weekday = '#{dia_equivalente}'
        AND tdc.discipline_id = #{disciplina_id}
    SQL

    total_aulas
  end

end
