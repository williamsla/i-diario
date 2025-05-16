class DescriptiveReportForm
  include ActiveModel::Model

  attr_accessor :classroom_id,
                :start_at,
                :end_at

  validates :classroom_id, presence: true

  def classroom
    @classroom ||= Classroom.by_id(classroom_id).first
  end

  def fetch_students
    student_enrollments = StudentEnrollmentsList.new(
      classroom: classroom,
      discipline: nil,
      start_at: start_at,
      end_at: end_at,
      search_type: :by_date_range,
    ).student_enrollments

    student_ids = student_enrollments.collect(&:student_id)
    @students = Student.where(id: student_ids).ordered
  end

  def fetch_exam_steps
    @descriptive_exams_steps ||= DescriptiveExam.by_classroom_id(classroom_id).ordered
  end

  def fetch_exam_values
    @descriptive_exam_values ||= DescriptiveExamStudent.by_classroom(classroom_id)
  end

  def is_annual
    classroom.first_exam_rule.opinion_type == 3
  end

  
  private
  
  
end
