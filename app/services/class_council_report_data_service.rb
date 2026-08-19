class ClassCouncilReportDataService
  SCORE_TYPES_WITH_GRADES = [
    ScoreTypes::NUMERIC,
    ScoreTypes::CONCEPT,
    ScoreTypes::NUMERIC_AND_CONCEPT
  ].freeze

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

  def self.reportable?(classroom)
    classrooms_grades_with_scores(classroom).any?
  end

  def self.header_payload(classroom)
    service = new(classroom)

    {
      classroom: classroom,
      school_year: classroom.year,
      course_name: classroom.course&.description,
      period_name: service.send(:period_label),
      grade_name: service.send(:grade_name_for_header)
    }
  end

  def self.classrooms_grades_with_scores(classroom)
    rounding_includes = [
      { rounding_table: :rounding_table_values },
      { rounding_table_concept: :rounding_table_values }
    ]

    classroom.classrooms_grades.includes(
      exam_rule: [
        { differentiated_exam_rule: rounding_includes },
        *rounding_includes
      ]
    ).select do |classrooms_grade|
      exam_rules_for(classrooms_grade).any? do |exam_rule|
        SCORE_TYPES_WITH_GRADES.include?(exam_rule.score_type.to_s)
      end
    end
  end

  def self.exam_rules_for(classrooms_grade)
    [classrooms_grade.exam_rule, classrooms_grade.exam_rule&.differentiated_exam_rule].compact
  end
  private_class_method :exam_rules_for

  def initialize(classroom)
    @classroom = classroom
    @steps_fetcher = StepsFetcher.new(classroom)
    @steps = @steps_fetcher.steps
    @disciplines = Discipline.by_classroom(classroom)
                             .not_grouper
                             .joins(:knowledge_area)
                             .where(knowledge_areas: { group_descriptors: false })
                             .order_by_sequence
    @discipline_ids = @disciplines.map(&:id)
    @general_configuration = GeneralConfiguration.first
    @year_start = year_start_date
    @year_end = @steps.last&.end_at || Date.current
  end

  def build
    preload_data!

    {
      classroom: @classroom,
      school_year: @classroom.year,
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
      score_type: StudentEnrollmentScoreTypeFilters::BOTH,
      search_type: :by_date_range,
      show_inactive: false
    ).student_enrollments

    student_enrollments = StudentEnrollment.where(id: enrollments.map(&:id))
                                           .includes(:student)
                                           .ordered
                                           .to_a

    # Multisseriada: ignora alunos de séries sem nota numérica/conceitual (ex.: 1ª série DONT_USE).
    filter_enrollments_with_gradable_exam_rule(student_enrollments)
  end

  def filter_enrollments_with_gradable_exam_rule(student_enrollments)
    return student_enrollments if student_enrollments.blank?

    grade_ids_with_scores = classrooms_grades_with_scores.map(&:grade_id)
    return [] if grade_ids_with_scores.blank?

    enrollment_ids = student_enrollments.map(&:id)
    enrollment_grade_ids = StudentEnrollmentClassroom
      .by_classroom(@classroom.id)
      .where(student_enrollment_id: enrollment_ids)
      .includes(:classrooms_grade)
      .each_with_object({}) do |sec, hash|
        next if sec.classrooms_grade.blank?

        hash[sec.student_enrollment_id] ||= []
        hash[sec.student_enrollment_id] << sec.classrooms_grade.grade_id
      end

    student_enrollments.select do |enrollment|
      (enrollment_grade_ids[enrollment.id] || []).any? { |grade_id| grade_ids_with_scores.include?(grade_id) }
    end
  end

  def classrooms_grades_with_scores
    @classrooms_grades_with_scores ||= self.class.classrooms_grades_with_scores(@classroom)
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
      hash[step.id] = TestSettingFetcher.current(@classroom, step)
    end
    @test_settings_by_step_discipline = {}
    preload_minimum_scores_by_step!
    @exemptions_by_student = load_exemptions_by_student
    @daily_notes_index = load_daily_notes_index
    @recovery_scores_index = load_recovery_scores_index
    @conceptual_exams_index = load_conceptual_exams_index
    @teacher_discipline_score_types = load_teacher_discipline_score_types
    @student_grade_ids = load_student_grade_ids
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
      .where.not(note: nil)
      .includes(
        daily_note: {
          avaliation: [
            :test_setting_test,
            :discipline,
            :recovery_diary_record,
            :avaliation_recovery_diary_record
          ]
        }
      )
      .to_a

    # Usa avaliation.discipline_id (não o delegate) para evitar chave nil após joins compostos.
    notes.group_by { |note| [note.student_id, note.daily_note.avaliation.discipline_id] }
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

  def load_conceptual_exams_index
    return {} if @student_ids.blank?

    step_numbers = @steps.map(&:step_number)
    return {} if step_numbers.blank?

    ConceptualExam
      .by_classroom_id(@classroom.id)
      .where(student_id: @student_ids, step_number: step_numbers)
      .includes(:conceptual_exam_values)
      .each_with_object({}) do |exam, hash|
        hash[[exam.student_id, exam.step_number]] = exam
      end
  end

  def load_teacher_discipline_score_types
    TeacherDisciplineClassroom
      .where(classroom_id: @classroom.id, discipline_id: @discipline_ids)
      .pluck(:discipline_id, :grade_id, :score_type)
      .each_with_object({}) do |(discipline_id, grade_id, score_type), hash|
        normalized = score_type.to_s
        hash[[discipline_id, grade_id]] = normalized
        # Fallback para vínculos antigos sem série ou lookup sem grade_id.
        hash[discipline_id] ||= normalized
      end
  end

  def load_student_grade_ids
    return {} if @student_ids.blank?

    grade_ids_with_scores = classrooms_grades_with_scores.map(&:grade_id)

    StudentEnrollmentClassroom
      .by_classroom(@classroom.id)
      .joins(:student_enrollment)
      .where(student_enrollments: { student_id: @student_ids })
      .includes(:classrooms_grade)
      .order(:id)
      .each_with_object({}) do |sec, hash|
        student_id = sec.student_enrollment.student_id
        grade_id = sec.classrooms_grade&.grade_id
        next if student_id.blank? || grade_id.blank?

        current = hash[student_id]
        # Prefer a series that has numeric/concept scores when the student has multiple links.
        if current.blank? || (!grade_ids_with_scores.include?(current) && grade_ids_with_scores.include?(grade_id))
          hash[student_id] = grade_id
        end
      end
  end

  def student_grade_id(student)
    @student_grade_ids[student.id]
  end

  def student_exam_rule(student)
    @student_exam_rules ||= {}
    return @student_exam_rules[student.id] if @student_exam_rules.key?(student.id)

    @student_exam_rules[student.id] = resolve_student_exam_rule(student)
  end

  # Prefere a regra da série já identificada no relatório (multisseriada-safe).
  # ExamRuleFetcher fica como fallback quando a série do aluno não está no índice local.
  def resolve_student_exam_rule(student)
    grade_id = student_grade_id(student)
    classrooms_grade = find_classrooms_grade_for_score(grade_id) if grade_id.present?

    if classrooms_grade&.exam_rule.present?
      exam_rule = classrooms_grade.exam_rule
      if student.uses_differentiated_exam_rule
        return exam_rule.differentiated_exam_rule.presence || exam_rule
      end

      return exam_rule
    end

    ExamRuleFetcher.fetch(@classroom, student)
  end

  def find_classrooms_grade_for_score(grade_id)
    classrooms_grades_with_scores.find { |cg| cg.grade_id == grade_id } ||
      @classroom.classrooms_grades.find { |cg| cg.grade_id == grade_id }
  end

  def student_uses_conceptual_evaluation?(student, discipline)
    exam_rule = student_exam_rule(student)
    return false if exam_rule.blank?

    score_type = exam_rule.score_type.to_s
    return true if score_type == ScoreTypes::CONCEPT

    if score_type == ScoreTypes::NUMERIC_AND_CONCEPT
      return teacher_discipline_is_concept?(discipline, student_grade_id(student))
    end

    false
  end

  def teacher_discipline_is_concept?(discipline, grade_id)
    score_type = @teacher_discipline_score_types[[discipline.id, grade_id]]
    score_type = @teacher_discipline_score_types[discipline.id] if score_type.blank?
    score_type.to_s == ScoreTypes::CONCEPT
  end

  def student_has_gradable_score_type?(student)
    exam_rule = student_exam_rule(student)
    # Aluno já filtrado por série com nota; se a regra não resolver, não bloqueia o cálculo.
    return true if exam_rule.blank?

    SCORE_TYPES_WITH_GRADES.include?(exam_rule.score_type.to_s)
  end

  def conceptual_score(student, discipline, step)
    exam = @conceptual_exams_index[[student.id, step.step_number]]
    return nil if exam.blank?

    value_record = exam.conceptual_exam_values.find { |value| value.discipline_id == discipline.id }
    concept_display_name(student, value_record&.value)
  end

  def concept_display_name(student, value)
    return nil if value.blank?

    exam_rule = student_exam_rule(student)
    rounding_table = exam_rule&.conceptual_rounding_table
    return value.to_s if rounding_table.blank?

    rounding_table_value = rounding_table.rounding_table_values.find { |rtv| rtv.value.to_s == value.to_s }
    rounding_table_value ? rounding_table_value.label.to_s : value.to_s
  end

  def calculate_score(student, discipline, step)
    return nil unless student_has_gradable_score_type?(student)
    return conceptual_score(student, discipline, step) if student_uses_conceptual_evaluation?(student, discipline)

    notes = daily_notes_in_step(student.id, discipline.id, step)
    recoveries = @recovery_scores_index[[student.id, discipline.id]] || []
    step_start = step.start_at.to_date
    step_end = step.end_at.to_date

    step_recoveries = recoveries.each_with_object({}) do |entry, hash|
      next unless entry[:test_date].to_date.between?(step_start, step_end)

      avaliation_id = entry[:avaliation_id]
      current = hash[avaliation_id]
      hash[avaliation_id] = current.present? ? [current, entry[:score]].max : entry[:score]
    end

    ClassCouncilAverageCalculator.new(
      classroom: @classroom,
      step: step,
      test_setting: test_setting_for(step, discipline),
      daily_note_students: notes,
      recovery_scores: step_recoveries,
      exempted_avaliation_ids: @exemptions_by_student[student.id] || Set.new
    ).calculate
  end

  def test_setting_for(step, discipline)
    cached = @test_settings_by_step[step.id]
    return cached if cached.present?

    key = [step.id, discipline.id]
    return @test_settings_by_step_discipline[key] if @test_settings_by_step_discipline.key?(key)

    @test_settings_by_step_discipline[key] =
      TestSettingFetcher.current(@classroom, step, discipline: discipline)
  end

  def daily_notes_in_step(student_id, discipline_id, step)
    notes = @daily_notes_index[[student_id, discipline_id]] || []
    step_start = step.start_at.to_date
    step_end = step.end_at.to_date

    notes.select do |note|
      test_date = note.daily_note&.avaliation&.test_date
      next false if test_date.blank?

      test_date.to_date.between?(step_start, step_end)
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
        score = @scores_cache[score_cache_key(student.id, discipline.id, step.step_number)]

        {
          discipline_id: discipline.id,
          score: score,
          absences: discipline_absences(student.id, discipline.id, step.step_number),
          below_minimum: score_below_minimum?(score, step)
        }
      }
    }
  end

  def preload_minimum_scores_by_step!
    # Prefer exam rules from series that actually have numeric/concept scores (multigrade-safe).
    minimum = classrooms_grades_with_scores
              .map { |cg| cg.exam_rule&.average_for_promotion }
              .compact
              .first
    minimum ||= @classroom.first_exam_rule&.average_for_promotion

    @minimum_scores_by_step = @steps.each_with_object({}) do |step, hash|
      hash[step.step_number] = minimum.presence
    end
  end

  def score_below_minimum?(score, step)
    return false unless score.is_a?(Numeric)

    numeric_score = score.to_f if score.present?
    return false if numeric_score.nil? || score.blank?

    minimum_score = @minimum_scores_by_step[step.step_number]
    return false if minimum_score.blank?

    numeric_score < minimum_score.to_f
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
    if @frequency_by_discipline.nil?
      # Do not use first_exam_rule alone: in multigrade the first series may be DONT_USE / GENERAL
      # while another series uses frequency by discipline.
      exam_rules = classrooms_grades_with_scores.map(&:exam_rule).compact
      exam_rules = [@classroom.first_exam_rule].compact if exam_rules.blank?

      @frequency_by_discipline = exam_rules.any? { |rule| rule.frequency_type == FrequencyTypes::BY_DISCIPLINE }
    end

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

    words = description.split(/\s+/).reject { |word| word.length <= 2 }
    return description[0, 3].upcase if words.empty?
    return words.first[0, 3].upcase if words.size == 1

    words.map { |word| word[0] }.join.upcase
  end
end
