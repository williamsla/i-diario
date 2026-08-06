class StudentEnrollmentClassroomFetcher
  def initialize(student, classroom, start_date, end_date)
    @student = student
    @classroom = classroom
    @start_date = start_date
    @end_date = end_date
  end

  def current_enrollment
    @current_enrollment ||= begin
      enrollments = batched_enrollments_by_student[@student.id] || []
      enrollments.last
    end
  end

  def previous_enrollments
    enrollments = batched_enrollments_by_student[@student.id] || []
    current_id = current_enrollment.try(:id)
    enrollments.reject { |enrollment| enrollment.id == current_id }
  end

  private

  def batched_enrollments_by_student
    ReportQueryCache.fetch([:enrollment_classrooms, @classroom.id, @start_date, @end_date]) do
      StudentEnrollmentClassroom.by_classroom(@classroom)
                                .by_date_range(@start_date, @end_date)
                                .active
                                .includes(student_enrollment: :student)
                                .ordered
                                .group_by { |sec| sec.student_enrollment.student_id }
    end
  end
end
