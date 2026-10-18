# frozen_string_literal: true

class AeeIndividualPlanOrigins < EnumerateIt::Base
  associate_values aee: 'aee',
                   regular: 'regular'

  sort_by :none
end
