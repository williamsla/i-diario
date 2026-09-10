class KnowledgeAreaLessonPlanReportForm
  include ActiveModel::Model

  attr_accessor :unity_id,
                :teacher_id,
                :classroom_id,
                :knowledge_area_id,
                :date_start,
                :date_end,
                :report_type,
                :author,
                :student_id

  validates :date_start, presence: true, date: true, timeliness: {
    on_or_before: :date_end,
    type: :date,
    on_or_before_message: :on_or_before_message
  }
  validates :date_end, presence: true, date: true, timeliness: {
    on_or_after: :date_start,
    type: :date,
    on_or_after_message: :on_or_after_message
  }
  validates :classroom_id,
            presence: true
  validate :must_have_knowledge_area_lesson_plan

  def knowledge_area_lesson_plan
    relation = KnowledgeAreaLessonPlan.by_classroom_id(classroom_id)
                                      .by_date_range(date_start.to_date, date_end.to_date)
                                      .by_author(author, teacher_id)
                                      .preload(
                                        :knowledge_areas,
                                        lesson_plan: [
                                          :student,
                                          { classroom: :unity },
                                          { contents_lesson_plans: :content },
                                          { objectives_lesson_plans: :objective }
                                        ]
                                      )
                                      .order_by_lesson_plan_date

    relation = relation.by_knowledge_area_id(knowledge_area_id) if knowledge_area_id.present?
    relation = relation.by_student_id(student_id) if individual_student_selected?

    relation
  end

  def knowledge_area_content_record
    relation = KnowledgeAreaContentRecord.by_classroom_id(classroom_id)
                                         .by_date_range(date_start.to_date, date_end.to_date)
                                         .by_author(author, teacher_id)
                                         .preload(
                                           :knowledge_areas,
                                           content_record: [
                                             :student,
                                             { classroom: :unity },
                                             { content_records_contents: :content },
                                             { objectives_content_records: :objective }
                                           ]
                                         )
                                         .order_by_content_record_date

    relation = relation.by_knowledge_area_id(knowledge_area_id) if knowledge_area_id.present?
    relation = relation.by_student_id(student_id) if individual_student_selected?

    relation
  end

  private

  def individual_student_selected?
    student_id.to_i.positive?
  end

  def must_have_knowledge_area_lesson_plan
    return if errors.present?

    if invalid_lesson_plan? || invalid_content_record?
      errors.add(:knowledge_area_lesson_plan, :must_have_knowledge_area_lesson_plan)
    end
  end

  def invalid_lesson_plan?
    report_type == ContentRecordReportTypes::LESSON_PLAN && !knowledge_area_lesson_plan.exists?
  end

  def invalid_content_record?
    report_type == ContentRecordReportTypes::CONTENT_RECORD && !knowledge_area_content_record.exists?
  end
end
