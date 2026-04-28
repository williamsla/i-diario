# frozen_string_literal: true

module AvaliationBatchGrades
  # :instrument_sum — regra só somatório (instrumentos da configuração)
  # :weighted_sum — regra somatório e aritmética (Av.1… com pesos livres)
  # :arithmetic — média aritmética
  module Mode
    module_function

    def batch_mode(test_setting, teacher_calculation)
      return :instrument_sum if test_setting.sum_calculation_type?
      return :weighted_sum if test_setting.arithmetic_and_sum_calculation_type?

      :arithmetic
    end
  end
end
