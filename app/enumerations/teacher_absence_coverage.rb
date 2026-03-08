# frozen_string_literal: true

class TeacherAbsenceCoverage < EnumerateIt::Base
  associate_values whole_day: 'whole_day',
                   by_classroom: 'by_classroom',
                   all_classrooms: 'all_classrooms'

  sort_by :none
end
