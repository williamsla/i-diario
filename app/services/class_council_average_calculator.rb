# Média numérica da etapa no conselho de classe.
# A conta é a mesma da coluna Etapa do relatório de avaliações numéricas:
# o tipo e o divisor vêm da configuração da etapa (TestSetting), não de uma
# quantidade fixa de avaliações.
class ClassCouncilAverageCalculator
  def initialize(student:, classroom:, discipline:, step:)
    @student = student
    @classroom = classroom
    @discipline = discipline
    @step = step
  end

  def calculate
    StudentAverageCalculator.new(@student).calculate(@classroom, @discipline, @step)
  end

  def self.average_for(test_setting:, score_sum:, scores_count:, weight_sum:)
    if test_setting.sum_calculation_type?
      score_sum / test_setting.default_division_weight
    elsif test_setting.arithmetic_and_sum_calculation_type?
      return if weight_sum.blank?
      return if weight_sum.to_d <= 0

      # Somatório com pesos livres, normalizado para a escala 0..10.
      score_sum / (weight_sum / 10.to_d)
    else
      scores_count.zero? ? 0 : score_sum / scores_count
    end
  end
end
