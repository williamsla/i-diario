class MaximumScoreFetcher

  def initialize(avaliation)
    @avaliation = avaliation
  end

  def maximum_score
    ts = avaliation.test_setting
    return ts.maximum_score if ts.arithmetic_calculation_type?

    min = ts.minimum_score.to_f

    if ts.arithmetic_and_sum_calculation_type?
      return safe_upper_for_note(min, avaliation.weight.to_f)
    end

    tst = avaliation.test_setting_test
    return ts.maximum_score if tst.blank?

    if tst.allow_break_up
      return safe_upper_for_note(min, avaliation.weight.to_f)
    end

    safe_upper_for_note(min, tst.weight.to_f)
  end

  private

  attr_accessor :avaliation

  # Garante teto >= nota mínima da configuração (evita ArgumentError no numericality de DailyNoteStudent quando peso é 0).
  def safe_upper_for_note(minimum_score, raw_upper)
    u = raw_upper.to_f
    return u if u >= minimum_score
    minimum_score
  end
end
