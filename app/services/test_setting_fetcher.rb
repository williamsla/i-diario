class TestSettingFetcher
  def self.current(classroom, step = nil, discipline: nil)
    new(classroom, step, discipline: discipline).current
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

  def school_term_type_step
    return if @step.blank?

    avaliation_school_term_type_step.presence || step_school_term_type_step
  end

  def avaliation_school_term_type_step
    scope = Avaliation.by_classroom_id(@classroom.id)
    scope = scope.by_discipline_id(@discipline.id) if @discipline.present?

    scope.by_test_date_between(@step.start_at, @step.end_at)
         .first
         .try(:test_setting)
         .try(:school_term_type_step)
  end

  def step_school_term_type_step
    steps_number = @step.school_calendar_parent.steps.count
    step_number = @step.step_number

    SchoolTermTypeStep.joins(:school_term_type)
                      .where(school_term_types: { steps_number: steps_number })
                      .find_by(step_number: step_number)
  end

  # TODO - Entender o porquê algumas vezes @classroom.grade_ids está vindo vazio
  # TODO - Está fazendo essa consulta muitas vezes no banco
  def general_by_school_test_setting
    @general_by_school_test_setting ||= TestSetting.where(year: @year, exam_setting_type: ExamSettingTypes::GENERAL_BY_SCHOOL)
               .by_unities(@classroom.unity)
               .where("grades && ARRAY[?]::integer[] OR grades = '{}'", @classroom.grades.pluck(:id))
               .first
  end

  def by_school_term_test_setting
    return if @step.blank?

    from_avaliations = test_setting_from_adjacent_calendar_steps
    return from_avaliations if from_avaliations.present?

    st = school_term_type_step
    return if st.blank?

    TestSetting.find_by(year: @year, school_term_type_step: st)
  end

  # EJA / calendários com várias etapas no mesmo período da config: as avaliações podem estar na
  # primeira etapa do calendário e o lançamento na segunda — usa a mesma disciplina e etapas vizinhas.
  def test_setting_from_adjacent_calendar_steps
    return if @discipline.blank?

    ordered = ordered_calendar_steps_for_step_parent
    return if ordered.blank?

    idx = ordered.index { |s| s.id == @step.id }
    return if idx.nil?

    [idx - 1, idx, idx + 1].each do |i|
      next if i.negative? || i >= ordered.size

      cal_step = ordered[i]
      ts = test_setting_from_avaliations_in_calendar_range(cal_step.start_at, cal_step.end_at)
      return ts if ts.present?
    end

    nil
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
      .first
      &.test_setting
  end
end
