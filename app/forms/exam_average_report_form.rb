class ExamAverageReportForm
  include ActiveModel::Model

  attr_accessor :unity_id,
                :classroom_id,
                :discipline_id,
                :school_calendar_steps,
                :school_calendar_classroom_steps

  validates :unity_id,      presence: true
  validates :classroom_id,  presence: true
  validates :discipline_id, presence: true
  validates :school_calendar_steps, presence: true, unless: :school_calendar_classroom_steps
  validates :school_calendar_classroom_steps, presence: true, unless: :school_calendar_steps

  def students_enrollments
    if classroom_steps.blank?
        StudentEnrollmentsList.new(
            classroom: classroom_id,
            discipline: discipline_id,
            start_at: steps.first.start_at,
            end_at: steps.last.end_at,
            score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
            search_type: :by_date_range,
            show_inactive: false
        ).student_enrollments
    else 
        StudentEnrollmentsList.new(
            classroom: classroom_id,
            discipline: discipline_id,
            start_at: classroom_steps.last.try(:start_at),
            end_at: classroom_steps.last.try(:end_at),
            score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
            search_type: :by_date_range,
            show_inactive: false
        ).student_enrollments
    end
  end

  def steps
    return unless school_calendar_steps

    school_calendar_steps
  end

  def classroom_steps
    return unless school_calendar_classroom_steps

    school_calendar_classroom_steps
  end

  

  private

  
  def remove_duplicated_enrollments(students_enrollments)
    students_enrollments = students_enrollments.select do |student_enrollment|
      enrollments_for_student = StudentEnrollment
        .by_student(student_enrollment.student_id)
        .by_classroom(classroom_id)

      if enrollments_for_student.count > 1
        enrollments_for_student.last != student_enrollment
      else
        true
      end
    end

    students_enrollments
  end
end
