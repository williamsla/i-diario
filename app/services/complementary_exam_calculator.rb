class ComplementaryExamCalculator
  def initialize(affected_score, student_id, discipline_id, classroom_id, step)
    @affected_score = affected_score
    @student_id = student_id.respond_to?(:id) ? student_id.id : student_id
    @discipline_id = discipline_id
    @classroom_id = classroom_id
    @step = step
  end

  def calculate(score)
    score = make_calculations(score)
    calculate_integral(maximum_score && maximum_score < score ? maximum_score : score)
  end

  private

  def calculate_integral(score)
    integral_records = exams_by_calculation(CalculationTypes::INTEGRAL)

    return score if integral_records.blank?

    integral_total = integral_records.map(&:score).compact.sum.to_f
    ((score + integral_total) / 2)
  end

  def maximum_score
    @maximum_score ||= test_setting.try(:maximum_score)
  end

  def test_setting
    classroom = cached_classroom
    return if classroom.blank?

    @test_setting ||= TestSettingFetcher.current(classroom, @step)
  end

  def cached_classroom
    ReportQueryCache.fetch([:classroom, classroom_id]) do
      Classroom.find_by(id: classroom_id)
    end
  end

  def make_calculations(score)
    return substitution_score if substitution_score.present?
    score += sum_substitution_score

    if substitution_if_greather_score.present? && substitution_if_greather_score > score
      substitution_if_greather_score
    else
      score
    end
  end

  attr_accessor :affected_score, :student_id, :discipline_id, :classroom_id, :step

  def substitution_score
    @substitution_score ||= begin
      record = exams_by_calculation(CalculationTypes::SUBSTITUTION).first
      record.try(:score)
    end
  end

  def substitution_if_greather_score
    @substitution_if_greather_score ||= begin
      record = exams_by_calculation(CalculationTypes::SUBSTITUTION_IF_GREATER).first
      record.try(:score)
    end
  end

  def sum_substitution_score
    @sum_substitution_score ||= exams_by_calculation(CalculationTypes::SUM).map(&:score).compact.sum.to_f
  end

  def exams_by_calculation(calculation)
    exam_ids = complementary_exam_ids(calculation)
    return [] if exam_ids.blank?

    students_by_id = ReportQueryCache.fetch([:complementary_exam_students, exam_ids]) do
      ComplementaryExamStudent.by_complementary_exam_id(exam_ids).group_by(&:student_id)
    end

    students_by_id[student_id] || []
  end

  def complementary_exam_ids(calculation)
    cache_key = [
      :complementary_exam_ids,
      classroom_id,
      discipline_id,
      step.start_at,
      step.end_at,
      affected_score,
      calculation
    ]

    ReportQueryCache.fetch(cache_key) do
      ComplementaryExam.by_classroom_id(classroom_id)
                       .by_discipline_id(discipline_id)
                       .by_date_range(step.start_at, step.end_at)
                       .by_affected_score(affected_score)
                       .by_calculation_type(calculation)
                       .pluck(:id)
    end
  end
end
