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

      begin
        created = Audited.audit_class.as_user(user) do
          CopyKnowledgeAreaTeachingPlanService.call(
            knowledge_area_teaching_plan_id,
            year,
            unities_ids,
            grades_ids,
            created_by_administrator: user.administrator?
          )
        end
      rescue CopyKnowledgeAreaTeachingPlanService::CopyKnowledgeAreaTeachingPlanError => error
        SystemNotificationCreator.create!(
          generic: true,
          title: I18n.t('copy_knowledge_area_teaching_plan_worker.empty_title'),
          description: error.message,
          users: [user]
        )
        return
      end

      if created.blank?
        SystemNotificationCreator.create!(
          generic: true,
          title: I18n.t('copy_knowledge_area_teaching_plan_worker.empty_title'),
          description: I18n.t('copy_knowledge_area_teaching_plan_worker.empty_description'),
          users: [user]
        )
      else
        SystemNotificationCreator.create!(
          source: created.first,
          title: I18n.t('copy_knowledge_area_teaching_plan_worker.title'),
          description: I18n.t('copy_knowledge_area_teaching_plan_worker.description'),
          users: [user]
        )
      end
    end
  end
end
