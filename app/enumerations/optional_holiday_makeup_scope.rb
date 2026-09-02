# frozen_string_literal: true

class OptionalHolidayMakeupScope < EnumerateIt::Base
  associate_values municipal: 'municipal',
                   by_school: 'by_school'

  sort_by :none
end
