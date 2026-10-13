# frozen_string_literal: true

class AeeAttendanceCompositions < EnumerateIt::Base
  associate_values :individual, :group
end
