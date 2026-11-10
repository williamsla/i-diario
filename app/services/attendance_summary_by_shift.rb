class AttendanceSummaryByShift
  class Error < StandardError; end

  TURNOS = {
    'matutino' => Periods::MATUTINAL,
    'vespertino' => Periods::VESPERTINE,
    'noturno' => Periods::NIGHTLY,
    'integral' => Periods::FULL
  }.freeze

  def initialize(cod_escola:, data:, turno:)
    @cod_escola = cod_escola.to_s.strip
    @data = data.to_s.strip
    @turno = turno.to_s.strip
  end

  def call
    validate!

    {
      cod_escola: @cod_escola,
      data: parsed_date.iso8601,
      turno: @turno,
      presentes: counts[:presentes],
      faltosos: counts[:faltosos],
      frequencias: frequency_count
    }
  end

  private

  def validate!
    raise Error, 'Informe a escola.' if @cod_escola.blank?
    raise Error, 'Informe a data.' if parsed_date.nil?
    raise Error, 'Turno inválido.' unless TURNOS.key?(@turno)
    raise Error, 'Escola não encontrada no i-Diário.' if unity.nil?
  end

  def parsed_date
    return @parsed_date if defined?(@parsed_date)

    @parsed_date = Date.iso8601(@data)
  rescue ArgumentError
    @parsed_date = nil
  end

  def unity
    return @unity if defined?(@unity)

    @unity = Unity.where(api_code: @cod_escola).order(id: :desc).first
  end

  # A frequência não traz o turno da refeição. O recorte é o turno da turma:
  # integral entra no matutino e no vespertino; noturno considera só turma noturna.
  def classroom_periods
    case @turno
    when 'matutino' then [Periods::MATUTINAL, Periods::FULL]
    when 'vespertino' then [Periods::VESPERTINE, Periods::FULL]
    when 'noturno' then [Periods::NIGHTLY]
    when 'integral' then [Periods::FULL]
    else []
    end.map(&:to_s)
  end

  def counts
    @counts ||= begin
      row = ActiveRecord::Base.connection.select_one(count_sql)

      {
        presentes: row&.fetch('presentes', 0).to_i,
        faltosos: row&.fetch('faltosos', 0).to_i
      }
    end
  end

  def count_sql
    ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, unity.id, parsed_date, classroom_periods])
      SELECT
        COUNT(*) FILTER (WHERE esteve_presente) AS presentes,
        COUNT(*) FILTER (WHERE NOT esteve_presente) AS faltosos
      FROM (
        SELECT daily_frequency_students.student_id,
               BOOL_OR(COALESCE(daily_frequency_students.present, FALSE)) AS esteve_presente
        FROM daily_frequency_students
        INNER JOIN daily_frequencies
          ON daily_frequencies.id = daily_frequency_students.daily_frequency_id
        INNER JOIN classrooms
          ON classrooms.id = daily_frequencies.classroom_id
        WHERE daily_frequencies.unity_id = ?
          AND daily_frequencies.frequency_date = ?
          AND classrooms.period::text IN (?)
          AND daily_frequency_students.active = TRUE
          AND daily_frequency_students.discarded_at IS NULL
          AND classrooms.discarded_at IS NULL
        GROUP BY daily_frequency_students.student_id
      ) alunos
    SQL
  end

  def frequency_count
    DailyFrequency.joins(:classroom)
                  .where(unity_id: unity.id, frequency_date: parsed_date)
                  .where('classrooms.period::text IN (?)', classroom_periods)
                  .count
  end
end
