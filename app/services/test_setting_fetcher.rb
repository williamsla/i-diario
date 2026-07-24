class TestSettingFetcher
  def self.current(classroom, step = nil, discipline: nil)
    step_key = step.respond_to?(:id) ? step.id : step.object_id
    discipline_key = discipline.respond_to?(:id) ? discipline.id : discipline
    cache_key = [:test_setting, classroom.id, step_key, discipline_key]

    ReportQueryCache.fetch(cache_key) do
      new(classroom, step, discipline: discipline).current
    end
  end

  def initialize(classroom, step = nil, discipline: nil)
    @classroom = classroom
    @step = step || current_step
    @discipline = discipline
  end

  def current
    raise ArgumentError if @classroom.blank?

    @year = @step.try(:school_calendar).try(:year) || @classroom.year

    general_by_school_test_setting.presence ||
      general_test_setting.presence ||
      by_school_term_test_setting.presence
  end

  private

  def general_test_setting
    TestSetting.find_by(
      exam_setting_type: ExamSettingTypes::GENERAL,
      year: @year
    )
  end

  def current_step
    StepsFetcher.new(@classroom).step_by_date(Date.current)
  end

  def step_school_term_type_step
    steps_number = @step.school_calendar_parent.steps.count
    step_number = @step.step_number

    SchoolTermTypeStep.joins(:school_term_type)
                      .joins('INNER JOIN test_settings ON test_settings.school_term_type_step_id = school_term_type_steps.id')
                      .where(
                        school_term_types: { steps_number: steps_number },
                        school_term_type_steps: { step_number: step_number },
                        test_settings: { year: @year, exam_setting_type: ExamSettingTypes::BY_SCHOOL_TERM }
                      )
                      .first
  end

  # TODO - Entender o porquê algumas vezes @classroom.grade_ids está vindo vazio
  # TODO - Está fazendo essa consulta muitas vezes no banco
  def general_by_school_test_setting
    grade_ids = classroom_grade_ids

    @general_by_school_test_setting ||= TestSetting.where(year: @year, exam_setting_type: ExamSettingTypes::GENERAL_BY_SCHOOL)
               .by_unities(@classroom.unity)
               .where("grades && ARRAY[?]::integer[] OR grades = '{}'", grade_ids)
               .first
  end

  def classroom_grade_ids
    ids = @classroom.grade_ids
    ids = @classroom.classrooms_grades.pluck(:grade_id) if ids.blank?

    ids.compact.uniq
  end

  def by_school_term_test_setting
    return if @step.blank?

    from_calendar = test_setting_by_step_number_and_calendar_steps_number
    return from_calendar if from_calendar.present?

    st = step_school_term_type_step
    if st.present?
      from_calendar_term = TestSetting.find_by(
        year: @year,
        exam_setting_type: ExamSettingTypes::BY_SCHOOL_TERM,
        school_term_type_step: st
      )
      return from_calendar_term if from_calendar_term.present?
    end

    test_setting_from_adjacent_calendar_steps
  end

  def test_setting_by_step_number_and_calendar_steps_number
    steps_number = @step.school_calendar_parent.steps.count

    TestSetting.joins(school_term_type_step: :school_term_type)
               .where(
                 year: @year,
                 exam_setting_type: ExamSettingTypes::BY_SCHOOL_TERM,
                 school_term_type_steps: { step_number: @step.step_number },
                 school_term_types: { steps_number: steps_number }
               )
               .first
  end

  # EJA / calendários com várias etapas no mesmo período da config: as avaliações podem estar na
  # primeira etapa do calendário e o lançamento na segunda — usa a mesma disciplina e etapas vizinhas.
  def test_setting_from_adjacent_calendar_steps
    return if @discipline.blank?

    ts = test_setting_from_avaliations_in_calendar_range(@step.start_at, @step.end_at)
    return ts if ts.present? && test_setting_matches_step_number?(ts)

    ordered = ordered_calendar_steps_for_step_parent
    return if ordered.blank?

    idx = ordered.index { |s| s.id == @step.id }
    return if idx.nil?

    [idx - 1, idx + 1].each do |i|
      next if i.negative? || i >= ordered.size

      cal_step = ordered[i]
      ts = test_setting_from_avaliations_in_calendar_range(cal_step.start_at, cal_step.end_at)
      next unless ts.present? && test_setting_matches_calendar_steps?(ts) && test_setting_matches_step_number?(ts)

      return ts
    end

    nil
  end

  def test_setting_matches_step_number?(test_setting)
    return false if test_setting.blank? || test_setting.school_term_type_step.blank? || @step.blank?

    test_setting.school_term_type_step.step_number == @step.step_number
  end

  def ordered_calendar_steps_for_step_parent
    parent = @step.school_calendar_parent
    if parent.respond_to?(:classroom_steps)
      parent.classroom_steps.order(:start_at)
    elsif parent.respond_to?(:steps)
      parent.steps.order(:start_at)
    else
      SchoolCalendarStep.none
    end
  end

  def test_setting_from_avaliations_in_calendar_range(start_at, end_at)
    Avaliation
      .by_classroom_id(@classroom.id)
      .by_discipline_id(@discipline.id)
      .by_test_date_between(start_at, end_at)
      .where.not(test_setting_id: nil)
      .joins(:test_setting)
      .where(test_settings: { exam_setting_type: ExamSettingTypes::BY_SCHOOL_TERM, year: @year })
      .order(:test_date, :id)
      .each do |avaliation|
        test_setting = avaliation.test_setting
        next unless test_setting_matches_calendar_steps?(test_setting)
        next unless test_setting_matches_step_number?(test_setting)

        return test_setting
      end

    nil
  end

  def test_setting_matches_calendar_steps?(test_setting)
    return false if test_setting.blank? || test_setting.school_term_type_step.blank? || @step.blank?

    @step.school_calendar_parent.steps.count == test_setting.school_term_type_step.school_term_type.steps_number
  end
end
