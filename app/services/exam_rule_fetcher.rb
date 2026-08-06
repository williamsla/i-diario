class ExamRuleFetcher
  def initialize(classroom, student)
    @classroom = classroom
    @student = student
  end

  def self.fetch(classroom, student)
    ReportQueryCache.fetch([:exam_rule, classroom.id, student.id]) do
      new(classroom, student).fetch
    end
  end

  def fetch
    return if @classroom.classrooms_grades.none? { |classroom_grade| classroom_grade.exam_rule.present? }

    student_enrollment_classroom = cached_enrollment_classrooms_by_student[@student.id]
    return if student_enrollment_classroom.blank?

    uses_differentiated_exam_rule(student_enrollment_classroom)
  end

  private

  def cached_enrollment_classrooms_by_student
    ReportQueryCache.fetch([:exam_rule_enrollments, @classroom.id]) do
      current_enrollments = {}
      StudentEnrollmentClassroom
        .by_classroom(@classroom)
        .by_date(Date.current)
        .includes(:classrooms_grade, student_enrollment: :student)
        .order(:id)
        .each do |sec|
          student_id = sec.student_enrollment.student_id
          current_enrollments[student_id] ||= sec
        end

      active_enrollments = StudentEnrollmentClassroom
        .by_classroom(@classroom)
        .active
        .includes(:classrooms_grade, student_enrollment: :student)
        .order(:id)
        .group_by { |sec| sec.student_enrollment.student_id }

      student_ids = (current_enrollments.keys + active_enrollments.keys).uniq
      student_ids.each_with_object({}) do |student_id, hash|
        hash[student_id] = current_enrollments[student_id] || active_enrollments[student_id]&.last
      end
    end
  end

  def uses_differentiated_exam_rule(student_enrollment_classroom)
    grade_id = student_enrollment_classroom.classrooms_grade&.grade_id
    return if grade_id.blank?

    classroom_grade = classroom_grades_by_grade_id[grade_id]
    return if classroom_grade&.exam_rule.blank?

    if @student.uses_differentiated_exam_rule
      classroom_grade.exam_rule.differentiated_exam_rule || classroom_grade.exam_rule
    else
      classroom_grade.exam_rule
    end
  end

  def classroom_grades_by_grade_id
    ReportQueryCache.fetch([:classroom_grades_by_grade, @classroom.id]) do
      ClassroomsGrade
        .by_classroom_id(@classroom.id)
        .includes(exam_rule: [
          :differentiated_exam_rule,
          { rounding_table: :rounding_table_values },
          { rounding_table_concept: :rounding_table_values }
        ])
        .index_by(&:grade_id)
    end
  end
end