class Select2StepSpecificRecoveryInput < Select2Input
  def input(wrapper_options)
    raise 'Classroom must be passed' unless options[:classroom].is_a? Classroom

    parse_collection
    super(wrapper_options)
  end

  def parse_collection
    steps = StepsFetcher.new(options[:classroom]).steps

    selected_steps = steps.select do |step|
      options[:classroom].first_exam_rule_with_recovery.recovery_exam_rules.any? do |recovery_specific|
        recovery_specific.steps.last.eql?(step.to_number)
      end
    end

    options[:elements] = selected_steps

    super
  end
  
end
