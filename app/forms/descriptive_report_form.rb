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
    exams = DescriptiveExam.by_classroom_id(classroom_id)
    
    # Se não for por disciplina, buscar apenas pareceres sem disciplina
    unless opinion_type_by_discipline?
      exams = exams.where(discipline_id: nil)
    end
    
    @descriptive_exams_steps ||= exams.ordered
  end

  def fetch_exam_values
    exam_students = DescriptiveExamStudent.by_classroom(classroom_id)
    
    # Se não for por disciplina, buscar apenas pareceres sem disciplina
    unless opinion_type_by_discipline?
      exam_students = exam_students.joins(:descriptive_exam)
                                    .merge(DescriptiveExam.where(discipline_id: nil))
    end
    
    @descriptive_exam_values ||= exam_students
  end

  def opinion_type_by_discipline?
    descriptive_opinion_types.any? do |opinion_type|
      [OpinionTypes::BY_STEP_AND_DISCIPLINE.to_s, OpinionTypes::BY_YEAR_AND_DISCIPLINE.to_s].include?(opinion_type.to_s)
    end
  end

  def is_annual
    types = descriptive_opinion_types
    types.any? && types.all? { |opinion_type| opinion_type.to_s == OpinionTypes::BY_YEAR.to_s }
  end

  private

  def descriptive_opinion_types
    @descriptive_opinion_types ||= classroom.descriptive_opinion_types
  end
end
