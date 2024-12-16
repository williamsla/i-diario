class ApiPostingTypes < EnumerateIt::Base
  associate_values :absence,
    :conceptual_exam,
    :descriptive_exam,
    :numerical_exam,
    :school_term_recovery,
    :final_recovery

  sort_by :none
end
