class ClassCouncilReportDataService
  STATUS_ABBREVIATIONS = {
    StudentEnrollmentStatus::APPROVED => 'Apr',
    StudentEnrollmentStatus::REPPROVED => 'Rep',
    StudentEnrollmentStatus::STUDYING => 'Cur',
    StudentEnrollmentStatus::TRANSFERRED => 'Trf',
    StudentEnrollmentStatus::RECLASSIFIED => 'Recl',
    StudentEnrollmentStatus::ABANDONMENT => 'Aba',
    StudentEnrollmentStatus::APPROVED_WITH_DEPENDENCY => 'Dep',
    StudentEnrollmentStatus::APPROVE_BY_COUNCIL => 'Ccl',
    StudentEnrollmentStatus::DISAPPROVED_BY_FAULTS => 'Rf',
    StudentEnrollmentStatus::DECEASED => 'Ob'
  }.freeze

  DISCIPLINE_ABBREVIATIONS = {
    /língua portuguesa|lingua portuguesa/i => 'LP',
    /matemática|matematica/i => 'MAT',
    /história|historia/i => 'HI',
    /geografia/i => 'GE',
    /ciências|ciencias/i => 'CI',
    /arte(s)?$/i => 'AR',
    /educação física|educacao fisica/i => 'EF',
    /ensino religioso/i => 'ER',
    /língua inglesa|lingua inglesa|inglês|ingles/i => 'ING',
    /convivência|convivencia/i => 'CO'
  }.freeze

  def initialize(classroom)
    @classroom = classroom
    @steps_fetcher = StepsFetcher.new(classroom)
    @steps = @steps_fetcher.steps
    @disciplines = Discipline.by_classroom(classroom).not_descriptor.not_grouper.order_by_sequence
    @discipline_ids = @disciplines.map(&:id)
    @general_configuration = GeneralConfiguration.first
    @year_start = year_start_date
    @year_end = @steps.last&.end_at || Date.current
  end

  def build
    preload_data!

    {
      classroom: @classroom,
      course_name: @classroom.course&.description,
      period_name: period_label,
      grade_name: grade_name_for_header,
      disciplines: @disciplines.map { |discipline| discipline_payload(discipline) },
      steps: @steps,
      students: @student_enrollments.map.with_index(1) { |student_enrollment, index|
        student_payload(student_enrollment, index)
      }
    }
  end

  private

  def preload_data!
    @student_enrollments = load_student_enrollments
    @student_ids = @student_enrollments.map { |enrollment| enrollment.student_id }

    preload_frequency_data!
    preload_discipline_absences! if frequency_by_discipline?
    preload_scores_data!
  end

  def load_student_enrollments
    start_at = @steps.first&.start_at
    end_at = @year_end

    enrollments = StudentEnrollmentsList.new(
      classroom: @classroom.id,
      discipline: nil,
      start_at: start_at,
      end_at: end_at,
      score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
      search_type: :by_date_range,
      show_inactive: false
    ).student_enrollments

    StudentEnrollment.where(id: enrollments.map(&:id)).includes(:student).ordered
  end

  def preload_frequency_data!
    @total_school_days = total_school_days_count

    base_scope = DailyFrequencyStudent
      .joins(:daily_frequency)
      .where(
        daily_frequencies: { classroom_id: @classroom.id, frequency_date: @year_start..@year_end },
        student_id: @student_ids,
        active: true
      )

    base_scope = base_scope.by_not_justified if @general_configuration.do_not_send_justified_absence

    absences = base_scope
      .where("COALESCE(daily_frequency_students.present, 'f') = 'f'")
      .group(:student_id)
      .count('DISTINCT daily_frequencies.frequency_date')

    @frequency_by_student = @student_ids.each_with_object({}) do |student_id, hash|
      absence_count = absences[student_id] || 0

      hash[student_id] = {
        frequency_percentage: frequency_percentage_from_school_days(absence_count),
        total_absences: absence_count
      }
    end
  end

  def total_school_days_count
    UnitySchoolDay.by_unity_id(@classroom.unity_id)
                  .by_date_between(@year_start, @year_end)
                  .count
  end

  def frequency_percentage_from_school_days(absence_count)
    return 0.0 if @total_school_days.zero?

    percentage = ((@total_school_days - absence_count).to_f / @total_school_days) * 100
    [percentage.round(2), 0.0].max
  end

  def preload_discipline_absences!
    return @discipline_absences = {} if @student_ids.blank? || @discipline_ids.blank?

    justification_filter = if @general_configuration.do_not_send_justified_absence
                             'AND daily_frequency_students.absence_justification_student_id IS NULL'
                           else
                             ''
                           end

    sql = <<-SQL.squish
      SELECT daily_frequency_students.student_id,
             daily_frequencies.discipline_id,
             step.step_number,
             COUNT(DISTINCT daily_frequencies.frequency_date) AS absences_count
      FROM daily_frequency_students
      INNER JOIN daily_frequencies
        ON daily_frequencies.id = daily_frequency_students.daily_frequency_id
      CROSS JOIN LATERAL step_by_classroom(?, daily_frequencies.frequency_date) AS step
      WHERE daily_frequencies.classroom_id = ?
        AND daily_frequencies.discipline_id IN (?)
        AND daily_frequency_students.student_id IN (?)
        AND daily_frequency_students.active = true
        AND COALESCE(daily_frequency_students.present, 'f') = 'f'
        AND daily_frequencies.frequency_date BETWEEN ? AND ?
        #{justification_filter}
      GROUP BY daily_frequency_students.student_id, daily_frequencies.discipline_id, step.step_number
    SQL

    sanitized_sql = ActiveRecord::Base.send(
      :sanitize_sql_array,
      [
        sql,
        @classroom.id,
        @classroom.id,
        @discipline_ids,
        @student_ids,
        @year_start,
        @year_end
      ]
    )

    @discipline_absences = ActiveRecord::Base.connection.select_all(sanitized_sql).each_with_object({}) do |row, hash|
      key = [row['student_id'].to_i, row['discipline_id'].to_i, row['step_number'].to_i]
      hash[key] = row['absences_count'].to_i
    end
  end

  def preload_scores_data!
    @test_settings_by_step = @steps.each_with_object({}) do |step, hash|
      hash[step] = TestSettingFetcher.current(@classroom, step)
    end
    @exemptions_by_student = load_exemptions_by_student
    @daily_notes_index = load_daily_notes_index
    @recovery_scores_index = load_recovery_scores_index
    @scores_cache = {}

    @student_enrollments.each do |enrollment|
      student = enrollment.student

      @disciplines.each do |discipline|
        @steps.each do |step|
          key = score_cache_key(student.id, discipline.id, step.step_number)
          @scores_cache[key] = calculate_score(student, discipline, step)
        end
      end
    end
  end

  def load_exemptions_by_student
    AvaliationExemption
      .where(student_id: @student_ids)
      .pluck(:student_id, :avaliation_id)
      .each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |(student_id, avaliation_id), hash|
        hash[student_id] << avaliation_id
      end
  end

  def load_daily_notes_index
    return {} if @student_ids.blank? || @discipline_ids.blank?

    notes = DailyNoteStudent
      .by_classroom_id(@classroom.id)
      .where(student_id: @student_ids)
      .joins(daily_note: :avaliation)
      .merge(Avaliation.by_discipline_id(@discipline_ids))
      .by_test_date_between(@year_start, @year_end)
      .includes(daily_note: { avaliation: [:test_setting_test, :recovery_diary_record] })
      .to_a

    notes.group_by { |note| [note.student_id, note.discipline_id] }
  end

  def load_recovery_scores_index
    return {} if @student_ids.blank? || @discipline_ids.blank?

    records = RecoveryDiaryRecordStudent
      .joins(recovery_diary_record: { avaliation_recovery_diary_record: :avaliation })
      .where(student_id: @student_ids)
      .merge(RecoveryDiaryRecord.by_classroom_id(@classroom.id).by_discipline_id(@discipline_ids))
      .merge(Avaliation.by_test_date_between(@year_start, @year_end))
      .where.not(score: nil)
      .pluck(:student_id, 'avaliations.discipline_id', 'avaliations.id', 'avaliations.test_date', :score)

    records.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(student_id, discipline_id, avaliation_id, test_date, score), hash|
      hash[[student_id, discipline_id]] << {
        avaliation_id: avaliation_id,
        test_date: test_date.to_date,
        score: score
      }
    end
  end

  def calculate_score(student, discipline, step)
    notes = daily_notes_in_step(student.id, discipline.id, step)
    recoveries = @recovery_scores_index[[student.id, discipline.id]] || []

    step_recoveries = recoveries.each_with_object({}) do |entry, hash|
      next unless entry[:test_date].between?(step.start_at, step.end_at)

      avaliation_id = entry[:avaliation_id]
      current = hash[avaliation_id]
      hash[avaliation_id] = current.present? ? [current, entry[:score]].max : entry[:score]
    end

    ClassCouncilAverageCalculator.new(
      classroom: @classroom,
      step: step,
      test_setting: @test_settings_by_step[step],
      daily_note_students: notes,
      recovery_scores: step_recoveries,
      exempted_avaliation_ids: @exemptions_by_student[student.id]
    ).calculate
  end

  def daily_notes_in_step(student_id, discipline_id, step)
    notes = @daily_notes_index[[student_id, discipline_id]] || []
    notes.select do |note|
      test_date = note.daily_note.avaliation.test_date
      test_date.between?(step.start_at, step.end_at)
    end
  end

  def score_cache_key(student_id, discipline_id, step_number)
    [student_id, discipline_id, step_number]
  end

  def discipline_payload(discipline)
    {
      id: discipline.id,
      abbreviation: discipline_abbreviation(discipline),
      description: discipline.description
    }
  end

  def student_payload(student_enrollment, order)
    student = student_enrollment.student
    frequency = @frequency_by_student[student.id] || { frequency_percentage: 0.0, total_absences: 0 }

    {
      order: order,
      name: student.name,
      situation: status_abbreviation(student_enrollment.status),
      frequency_percentage: frequency[:frequency_percentage],
      total_absences: frequency[:total_absences],
      steps: @steps.map { |step| step_payload(student, step) }
    }
  end

  def step_payload(student, step)
    {
      number: step.step_number,
      label: "#{step.step_number}º Bimestre",
      disciplines: @disciplines.map { |discipline|
        {
          discipline_id: discipline.id,
          score: @scores_cache[score_cache_key(student.id, discipline.id, step.step_number)],
          absences: discipline_absences(student.id, discipline.id, step.step_number)
        }
      }
    }
  end

  def discipline_absences(student_id, discipline_id, step_number)
    return 0 unless frequency_by_discipline?

    (@discipline_absences || {})[[student_id, discipline_id, step_number]] || 0
  end

  def year_start_date
    school_calendar = @steps_fetcher.school_calendar
    if school_calendar&.steps&.any?
      school_calendar.first_day
    else
      Date.new(@classroom.year, 1, 1)
    end
  end

  def grade_name_for_header
    return 'Multisseriada' if @classroom.multi_grade?

    @classroom.first_grade&.description.to_s
  end

  def period_label
    return '' if @classroom.period.blank?

    key = Periods.key_for(@classroom.period)
    I18n.t("enumerations.periods.#{key}", default: @classroom.period)
  rescue ArgumentError
    @classroom.period
  end

  def frequency_by_discipline?
    @frequency_by_discipline = @classroom.first_exam_rule&.frequency_type == FrequencyTypes::BY_DISCIPLINE if @frequency_by_discipline.nil?
    @frequency_by_discipline
  end

  def status_abbreviation(status)
    STATUS_ABBREVIATIONS[status.to_i] || '—'
  end

  def discipline_abbreviation(discipline)
    description = discipline.description.to_s

    DISCIPLINE_ABBREVIATIONS.each do |pattern, abbreviation|
      return abbreviation if description.match?(pattern)
    end

    words = description.split(/\s+/).reject { |word| word.length < 2 }
    return description[0, 3].upcase if words.size == 1

    words.map { |word| word[0] }.join.upcase[0, 3]
  end
end
