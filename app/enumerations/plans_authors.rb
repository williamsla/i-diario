class PlansAuthors < EnumerateIt::Base
  associate_values :my_plans, :others, :all

  sort_by :none
end
