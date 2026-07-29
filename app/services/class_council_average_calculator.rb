# Calcula média por etapa a partir de notas já carregadas em memória (sem consultas extras).
class ClassCouncilAverageCalculator
  def initialize(classroom:, step:, test_setting:, daily_note_students:, recovery_scores:,
                 exempted_avaliation_ids: Set.new)
    @classroom = classroom
    @step = step
    @test_setting = test_setting
    @daily_note_students = daily_note_students
    @recovery_scores = recovery_scores
    @exempted_avaliation_ids = exempted_avaliation_ids
  end

  def calculate
    return nil if @test_setting.blank?

    scores = unique_avaliation_scores
    return nil if scores.blank?

    result = calculate_average_by_settings(scores)
    return nil if result.blank?

    ScoreRounder.new(@classroom, RoundedAvaliations::NUMERICAL_EXAM, @step).round(result)
  end

  private

  def unique_avaliation_scores
    avaliations = []

    @daily_note_students.each do |daily_note_student|
      avaliation = daily_note_student.daily_note&.avaliation
      next if avaliation.blank?
      next if exempted?(avaliation.id)
      # Ignora lançamentos sem nota (placeholders do diário) e transferências sem valor local.
      next if daily_note_student.note.blank?

      avaliations << { value: daily_note_student.recovered_note.to_f, avaliation_id: avaliation.id }
    end

    @recovery_scores.each do |avaliation_id, score|
      next if exempted?(avaliation_id)
      next if score.blank?

      avaliations << { value: score.to_f, avaliation_id: avaliation_id }
    end

    avaliations.group_by { |entry| entry[:avaliation_id] }.map do |_avaliation_id, entries|
      entries.map { |entry| entry[:value] }.max
    end
  end

  def unique_avaliation_weights
    weights = []

    @daily_note_students.each do |daily_note_student|
      avaliation = daily_note_student.daily_note&.avaliation
      next if avaliation.blank?
      next if exempted?(avaliation.id)
      next if daily_note_student.note.blank?
      next if avaliation.weight.blank?

      weights << { value: avaliation.weight, avaliation_id: avaliation.id }
    end

    weights.group_by { |entry| entry[:avaliation_id] }.map do |_avaliation_id, entries|
      entries.map { |entry| entry[:value] }.max
    end
  end

  def calculate_average_by_settings(scores)
    score_sum = scores.sum

    if @test_setting.sum_calculation_type?
      score_sum / @test_setting.default_division_weight
    elsif @test_setting.arithmetic_and_sum_calculation_type?
      weight_values = unique_avaliation_weights
      return nil if weight_values.blank?

      weight_sum = weight_values.sum
      return nil if weight_sum.to_d <= 0

      score_sum / (weight_sum / 10.to_d)
    else
      score_sum / scores.size
    end
  end

  def exempted?(avaliation_id)
    @exempted_avaliation_ids.include?(avaliation_id)
  end
end
