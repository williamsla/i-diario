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

      total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_semana_nome, true, agrupar: false)
      if total_aulas == 0
        total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_semana_nome, false, agrupar: false)
      end
    end

    total_aulas
  end

  private

  def count_lessons_from_boards(turma_id, disciplina_id, dia_semana_nome, ativo, agrupar: false)
    # Define filtro de ativo/inativo
    ativo_condicao = if ativo
      <<~SQL
        AND lb.discarded_at IS NULL
      SQL
    else
      <<~SQL
        AND lb.discarded_at IS NOT NULL
      SQL
    end

    # Define agrupamento e ordenação, se for solicitado
    group_and_order = <<~SQL if agrupar
      GROUP BY lblw.weekday
      ORDER BY COUNT(lbl.id) DESC
      LIMIT 1
    SQL

    sql = <<-SQL
      SELECT COUNT(lbl.id) AS total_aulas
      FROM lessons_boards lb
      INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id
      INNER JOIN lessons_board_lessons lbl ON lbl.lessons_board_id = lb.id
      INNER JOIN lessons_board_lesson_weekdays lblw ON lblw.lessons_board_lesson_id = lbl.id
      INNER JOIN teacher_discipline_classrooms tdc ON tdc.classroom_id = cg.classroom_id
        AND tdc.id = lblw.teacher_discipline_classroom_id
        AND tdc.discarded_at IS NULL
      WHERE cg.classroom_id = #{turma_id}
        AND lblw.weekday = '#{dia_semana_nome}'
        AND tdc.discipline_id = #{disciplina_id}
        #{ativo_condicao}
      #{group_and_order}
    SQL

    total_aulas = ActiveRecord::Base.connection.exec_query(sql).first&.dig("total_aulas") || 0
    total_aulas
  end

  def count_lessons_by_saturday(turma_id, disciplina_id, data)
    # Busca o dia da semana equivalente no arquivo de configuração
    dia_equivalente = get_weekday_for_saturday(data)

    # Se não houver mapeamento configurado, retorna 0
    return 0 if dia_equivalente.blank?

    # Tenta quadros ativos
    total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_equivalente, true, agrupar: false)
    if total_aulas == 0
      # Se não houver, tenta inativos
      total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_equivalente, false, agrupar: false)
    end

    if total_aulas == 0
      # Se não houver aulas no dia equivalente, usa o dia que tiver mais aulas da referida disciplina
      total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_equivalente, true, agrupar: true)
      if total_aulas == 0
        total_aulas = count_lessons_from_boards(turma_id, disciplina_id, dia_equivalente, false, agrupar: true)
      end
    end
    
    total_aulas
  end

  def get_weekday_for_saturday(date)
    # Carrega o mapeamento de sábados letivos do arquivo de configuração
    sabados_letivos_map = load_sabados_letivos_config
    
    # Busca o dia da semana equivalente para a data informada
    date_key = date.strftime("%Y-%m-%d")
    sabados_letivos_map[date_key]
  end

  def load_sabados_letivos_config
    @sabados_letivos_map ||= begin
      config_path = Rails.root.join('config', 'sabados_letivos.yml')
      
      if File.exist?(config_path)
        YAML.load_file(config_path) || {}
      else
        {}
      end
    end
  end

end
