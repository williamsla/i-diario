class ContentsForKnowledgeAreaRecordFetcher < ContentsRecordFetcher
  def initialize(teacher, classroom, knowledge_areas, date, student_id = nil)
    @teacher = teacher
    @classroom = classroom
    @knowledge_areas = [knowledge_areas].flatten
    @date = date
    @student_id = student_id
  end

  private

  def lesson_plans
    # Não usar cache para garantir que a data seja sempre verificada corretamente
    @lesson_plans = KnowledgeAreaLessonPlan.includes(lesson_plan: :contents)
                                           .by_classroom_id(@classroom.id)
                                           .by_knowledge_area_id(@knowledge_areas.map(&:id))
                                           .by_student_id(@student_id)
                                           .by_date(@date)
  end

  def lesson_plans_objectives
    # Não usar cache para garantir que a data seja sempre verificada corretamente
    @lesson_plans_objectives = KnowledgeAreaLessonPlan.includes(lesson_plan: :objectives)
                                                      .by_classroom_id(@classroom.id)
                                                      .by_knowledge_area_id(@knowledge_areas.map(&:id))
                                                      .by_student_id(@student_id)
                                                      .by_date(@date)
  end

  def teaching_plans
    @teaching_plans ||= KnowledgeAreaTeachingPlan.includes(teaching_plan: :contents)
                                                 .by_unity(@classroom.unity_id)
                                                 .by_grade(@classroom.grade_ids)
                                                 .by_knowledge_area(@knowledge_areas.map(&:id))
                                                 .by_student_id(@student_id)
                                                 .by_year(school_calendar_year)
                                                 .by_teacher_id(@teacher.id)
  end
end
