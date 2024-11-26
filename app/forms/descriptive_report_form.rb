class DescriptiveReportForm
  include ActiveModel::Model

  attr_accessor :classroom_id,
                :start_at,
                :end_at

  validates :classroom_id, presence: true
  
  def fetch_students
    student_enrollments = StudentEnrollmentsList.new(
      classroom: Classroom.by_id(classroom_id).first,
      discipline: nil,
      start_at: start_at,
      end_at: end_at,
      search_type: :by_date_range,
    ).student_enrollments

    student_ids = student_enrollments.collect(&:student_id)
    @students = Student.where(id: student_ids).ordered
  end

  def fetch_exam_values
    @descriptive_exam_values ||= DescriptiveExamStudent.by_classroom(classroom_id)
  end

  
  private
  
  
end
