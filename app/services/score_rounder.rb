class ScoreRounder
  def initialize(classroom, rounded_avaliation, step = nil)
    @classroom = classroom
    @rounded_avaliation = rounded_avaliation
    @step = step
  end

  def round(score)
    return if score.nil?

    score_decimal_part = decimal_part(score)
    rounding_table_value = custom_rounding_table_value(score_decimal_part)
    rounded_score = rounded_score_by_action(score, rounding_table_value)

    truncate_score(rounded_score.to_f)
  end

  private

  def rounded_score_by_action(score, rounding_table_value)
    return score unless score.is_a?(Numeric)

    rounded_score = score

    if rounding_table_value.present?
      rounded_score = case rounding_table_value.action
                      when RoundingTableAction::NONE
                        score
                      when RoundingTableAction::BELOW
                        round_to_below(score)
                      when RoundingTableAction::ABOVE
                        round_to_above(score)
                      when RoundingTableAction::SPECIFIC
                        round_to_exact_decimal(score, rounding_table_value.exact_decimal_place)
                      end
    end

    rounded_score
  end

  def custom_rounding_table_value(score_decimal_part)
    rounding_table_id = custom_rounding_table_id

    return if rounding_table_id.blank?

    values_by_label = ReportQueryCache.fetch([:custom_rounding_table_values, rounding_table_id]) do
      CustomRoundingTableValue
        .where(custom_rounding_table_id: rounding_table_id)
        .index_by { |value| value.label.to_s }
    end

    values_by_label[score_decimal_part.to_s]
  end

  def custom_rounding_table_id
    ReportQueryCache.fetch([:custom_rounding_table_id, @classroom.id, @rounded_avaliation]) do
      CustomRoundingTable.by_year(@classroom.year)
                         .by_unity(@classroom.unity_id)
                         .by_grade(@classroom.grade_ids)
                         .by_avaliation(@rounded_avaliation)
                         .first.try(:id)
    end
  end

  def decimal_part(value)
    parts = value.to_s.split('.')
    parts.count > 1 ? parts[1][0].to_s : 0
  end

  def round_to_exact_decimal(score, exact_decimal_place)
    "#{score.floor}.#{exact_decimal_place}".to_f
  end

  def round_to_above(score)
    score.ceil
  end

  def round_to_below(score)
    score.floor
  end

  def number_of_decimal_places
    TestSettingFetcher.current(@classroom, @step)&.number_of_decimal_places || 1
  end

  def truncate_score(score)
    parts = score.to_s.split('.')
    integer_part = parts[0]
    decimal_part = decimal_parts(parts[1])

    "#{integer_part}.#{decimal_part}".to_f
  end

  def decimal_parts(part)
    return if part.nil?

    decimal_places = number_of_decimal_places - 1

    decimal_part = part[0..decimal_places]

    if number_of_decimal_places > decimal_part.size
      missing = number_of_decimal_places - decimal_part.size
      decimal_part = decimal_part + count_zeros(missing)
    end

    decimal_part
  end

  def count_zeros(missing)
    "0" * missing
  end
end
