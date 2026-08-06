class ContentsForDisciplineRecordFetcher < ContentsRecordFetcher
  def initialize(teacher, classroom, discipline, date, student_id = nil)
    @teacher = teacher
    @classroom = classroom
    @discipline = discipline
    @date = date
    @student_id = student_id
  end

  private

  def lesson_plans
    # Não usar cache para garantir que a data seja sempre verificada corretamente
    @lesson_plans = DisciplineLessonPlan.includes(lesson_plan: :contents)
                        .by_classroom_id(@classroom.id)
                        .by_discipline_id(@discipline.id)
                        .by_student_id(@student_id)
                        .by_date(@date)
  end

  def lesson_plans_objectives
    # Não usar cache para garantir que a data seja sempre verificada corretamente
    @lesson_plans_objectives = DisciplineLessonPlan.includes(lesson_plan: :objectives)
                        .by_classroom_id(@classroom.id)
                        .by_discipline_id(@discipline.id)
                        .by_student_id(@student_id)
                        .by_date(@date)
  end

  def teaching_plans
    @teaching_plans ||= DisciplineTeachingPlan.includes(teaching_plan: [:contents, :objectives])
                                              .by_unity(@classroom.unity_id)
                                              .by_grade(@classroom.grade_ids)
                                              .by_discipline(@discipline.id)
                                              .by_student_id(@student_id)
                                              .by_year(school_calendar_year)
  end
end
