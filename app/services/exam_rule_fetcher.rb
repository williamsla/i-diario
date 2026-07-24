class ExamRuleFetcher
  def initialize(classroom, student)
    @classroom = classroom
    @student = student
  end

  def self.fetch(classroom, student)
    new(classroom, student).fetch
  end

  def fetch
    return if @classroom.classrooms_grades.none? { |classroom_grade| classroom_grade.exam_rule.present? }

    student_enrollment_classroom = StudentEnrollmentClassroom.by_student(@student)
                                                             .by_classroom(@classroom)
                                                             .by_date(Date.current)
                                                             .first

    if student_enrollment_classroom.blank?
      student_enrollment_classroom = StudentEnrollmentClassroom.by_student(@student)
                                                               .by_classroom(@classroom)
                                                               .active
                                                               .last
    end

    return if student_enrollment_classroom.blank?

    uses_differentiated_exam_rule(student_enrollment_classroom)
  end

  private

  def uses_differentiated_exam_rule(student_enrollment_classroom)
    grade_id = student_enrollment_classroom.classrooms_grade&.grade_id
    return if grade_id.blank?

    # Query by classroom_id to avoid a partially-loaded classrooms_grades association
    # (e.g. after classrooms_grades.first) hiding other series in multigrade classrooms.
    classroom_grade = ClassroomsGrade.by_classroom_id(@classroom.id).find_by(grade_id: grade_id)
    return if classroom_grade&.exam_rule.blank?

    if @student.uses_differentiated_exam_rule
      classroom_grade.exam_rule.differentiated_exam_rule || classroom_grade.exam_rule
    else
      classroom_grade.exam_rule
    end
  end
end
