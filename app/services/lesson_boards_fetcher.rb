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
end
