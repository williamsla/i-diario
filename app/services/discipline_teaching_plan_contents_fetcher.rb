class DisciplineTeachingPlanContentsFetcher < TeachingPlanContentsFetcher
  def initialize(teacher, classroom, discipline, start_date, end_date, student_id)
    @teacher = teacher
    @classroom = classroom
    @discipline = discipline
    @start_date = start_date
    @end_date = end_date
    @student_id = student_id
  end

  protected

  def base_query
    DisciplineTeachingPlan.by_unity(@classroom.unity_id)
                          .by_grade(@classroom.classrooms_grades.map(&:grade_id))
                          .by_discipline(@discipline)
                          .by_student_id(@student_id)
                          .by_year(school_calendar_year)
                          .by_school_term_type_step_id(school_term_type_steps_ids)
                          .order_by_school_term_type_step
                          .includes(teaching_plan: :contents)
  end
end
