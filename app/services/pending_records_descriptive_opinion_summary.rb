class PendingRecordsDescriptiveOpinionSummary
  def initialize(classroom:, step:, start_date:, end_date:, pending_records:, teacher_id: nil)
    @classroom = classroom
    @step = step
    @start_date = start_date
    @end_date = end_date
    @pending_records = pending_records
    @teacher_id = teacher_id
    @exam_rule = classroom.first_exam_rule
  end

  def apply!
    return @pending_records unless descriptive_opinion_enabled?

    if opinion_by_discipline?
      apply_by_discipline!
    else
      apply_classroom_wide!
    end

    @pending_records
  end

  def opinion_by_discipline?
    return false if @exam_rule.blank?

    [
      OpinionTypes::BY_STEP_AND_DISCIPLINE,
      OpinionTypes::BY_YEAR_AND_DISCIPLINE
    ].include?(@exam_rule.opinion_type)
  end

  private

  def descriptive_opinion_enabled?
    @exam_rule.present? && @exam_rule.allow_descriptive_exam?
  end

  def apply_classroom_wide!
    count = count_students_without_opinion(discipline_id: nil)

    @pending_records.each do |record|
      record[:students_without_opinion_count] = count
    end
  end

  def apply_by_discipline!
    discipline_ids = @pending_records.map { |record| normalize_discipline_id(record[:discipline_id]) }.compact.uniq

    counts_by_discipline = discipline_ids.each_with_object({}) do |discipline_id, hash|
      hash[discipline_id] = count_students_without_opinion(discipline_id: discipline_id)
    end

    @pending_records.each do |record|
      discipline_id = normalize_discipline_id(record[:discipline_id])
      record[:students_without_opinion_count] = discipline_id ? counts_by_discipline[discipline_id] || 0 : 0
    end
  end

  def count_students_without_opinion(discipline_id:)
    enrolled_ids = enrolled_student_ids(discipline_id: discipline_id)
    return 0 if enrolled_ids.blank?

    filled_ids = students_with_filled_opinion_ids(discipline_id: discipline_id)
    (enrolled_ids - filled_ids).size
  end

  def enrolled_student_ids(discipline_id:)
    ids = enrolled_student_ids_from_retriever(discipline_id: discipline_id)
    return ids if ids.present?

    student_ids_from_descriptive_exams_in_scope(discipline_id: discipline_id)
  end

  def enrolled_student_ids_from_retriever(discipline_id:)
    period_start, period_end = enrollment_period_bounds
    discipline = opinion_by_discipline? ? Discipline.find_by(id: discipline_id) : nil
    enrollment_start = period_start

    StudentEnrollmentClassroomsRetriever.call(
      classrooms: @classroom,
      disciplines: discipline,
      opinion_type: @exam_rule.opinion_type,
      start_at: period_start,
      end_at: period_end,
      search_type: :by_date_range,
      period: teacher_period_for(discipline_id)
    ).map do |enrollment|
      student = enrollment[:student]
      student_enrollment = enrollment[:student_enrollment]
      left_at = enrollment[:student_enrollment_classroom].left_at

      next if inactive_before_period?(left_at, enrollment_start)
      next if exempted_from_discipline?(student_enrollment, discipline_id)

      student.id
    end.compact.uniq
  end

  def student_ids_from_descriptive_exams_in_scope(discipline_id:)
    DescriptiveExamStudent
      .joins(:descriptive_exam)
      .merge(descriptive_exams_scope(discipline_id: discipline_id))
      .distinct
      .pluck(:student_id)
  end

  def students_with_filled_opinion_ids(discipline_id:)
    DescriptiveExamStudent
      .joins(:descriptive_exam)
      .merge(descriptive_exams_scope(discipline_id: discipline_id))
      .pluck(:student_id, :value)
      .select { |_, value| DescriptiveExamValue.present?(value) }
      .map(&:first)
      .uniq
  end

  def inactive_before_period?(left_at, enrollment_start)
    return false if left_at.blank? || enrollment_start.blank?

    left_at.to_date < enrollment_start.to_date
  end

  def exempted_from_discipline?(student_enrollment, discipline_id)
    return false if discipline_id.blank?

    relevant_step_numbers.any? do |step_number|
      student_enrollment.exempted_disciplines
                        .by_discipline(discipline_id)
                        .by_step_number(step_number)
                        .any?
    end
  end

  def relevant_step_numbers
    if semester_calendar_applies?
      semester_step_numbers
    else
      [@step.step_number]
    end
  end

  def teacher_period_for(discipline_id)
    return nil if discipline_id.blank? || @teacher_id.blank?

    period = TeacherPeriodFetcher.new(@teacher_id, @classroom.id, discipline_id).teacher_period
    period == Periods::FULL.to_i ? nil : period
  end

  def descriptive_exams_scope(discipline_id:)
    scope = DescriptiveExam.by_classroom_id(@classroom.id)
    scope = apply_opinion_period_scope(scope)

    if opinion_by_discipline?
      scope = scope.by_discipline_id(discipline_id)
    end

    scope
  end

  def apply_opinion_period_scope(scope)
    if opinion_by_year?
      period_start, period_end = enrollment_period_bounds
      scope.by_recorded_at_between(period_start, period_end)
    elsif semester_calendar_applies?
      scope.where(step_number: semester_step_numbers)
    else
      scope.by_step_number(@step.step_number)
    end
  end

  def enrollment_period_bounds
    if opinion_by_year?
      school_year_bounds
    elsif semester_calendar_applies?
      semester_bounds
    else
      [@start_date, @end_date]
    end
  end

  def school_year_bounds
    steps = StepsFetcher.new(@classroom).steps.to_a
    return [@start_date, @end_date] if steps.blank?

    [steps.map(&:start_at).min, steps.map(&:end_at).max]
  end

  def semester_bounds
    pair = semester_steps
    return [@start_date, @end_date] if pair.blank?

    [pair.first.start_at, pair.last.end_at]
  end

  def semester_steps
    @semester_steps ||= DescriptiveExamSemesterCalendar.semester_pair_containing(
      @classroom,
      @step.step_number
    )
  end

  def semester_step_numbers
    semester_steps.map(&:step_number)
  end

  def semester_calendar_applies?
    return false if opinion_by_year?

    semester_steps.present?
  end

  def opinion_by_year?
    return false if @exam_rule.blank?

    [OpinionTypes::BY_YEAR, OpinionTypes::BY_YEAR_AND_DISCIPLINE].include?(@exam_rule.opinion_type)
  end

  def normalize_discipline_id(discipline_id)
    discipline_id.present? ? discipline_id.to_i : nil
  end
end
