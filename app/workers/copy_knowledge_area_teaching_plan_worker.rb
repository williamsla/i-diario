class CopyKnowledgeAreaTeachingPlanWorker
  include Sidekiq::Worker

  def perform(
    entity_id,
    user_id,
    knowledge_area_teaching_plan_id,
    year,
    unities_ids,
    grades_ids
  )
    Entity.find(entity_id).using_connection do
      user = User.find(user_id)
      model = KnowledgeAreaTeachingPlan.find(knowledge_area_teaching_plan_id)

      Audited.audit_class.as_user(user) do
        CopyKnowledgeAreaTeachingPlanService.call(
          knowledge_area_teaching_plan_id,
          year,
          unities_ids,
          grades_ids,
          created_by_administrator: user.has_administrator_access_level?
        )
      end

      SystemNotificationCreator.create!(
        source: model,
        title: I18n.t('copy_knowledge_area_teaching_plan_worker.title'),
        description: I18n.t('copy_knowledge_area_teaching_plan_worker.description'),
        users: [user]
      )
    end
  end
end
