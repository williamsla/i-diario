class CoveragesOfEvent < EnumerateIt::Base
  associate_values :by_unity, :by_grade, :by_classroom

  sort_by :none
end
