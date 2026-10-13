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

    student_ids = student_enrollments.select { |enrollment| descriptive_exam_permitted?(enrollment.student) }
                                     .map(&:student_id)

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

  def descriptive_exam_permitted?(student)
    classrooms_grade = classrooms_grades_by_student_id[student.id]
    return false if classrooms_grade.blank?

    exam_rule = classrooms_grade.exam_rule
    exam_rule = exam_rule.differentiated_exam_rule || exam_rule if student.uses_differentiated_exam_rule
    return false if exam_rule.blank?

    exam_rule.allow_descriptive_exam?
  end

  def classrooms_grades_by_student_id
    @classrooms_grades_by_student_id ||= classroom.classrooms_grades
                                                  .includes(:student_enrollments, exam_rule: :differentiated_exam_rule)
                                                  .each_with_object({}) do |classrooms_grade, memo|
      classrooms_grade.student_enrollments.each do |enrollment|
        memo[enrollment.student_id] ||= classrooms_grade
      end
    end
  end
end
