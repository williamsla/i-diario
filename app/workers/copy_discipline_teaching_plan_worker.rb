class CopyDisciplineTeachingPlanWorker
  include Sidekiq::Worker

  def perform(
    entity_id,
    user_id,
    discipline_teaching_plan_id,
    year,
    unities_ids,
    grades_ids
  )
    Entity.find(entity_id).using_connection do
      user = User.find(user_id)

      discipline_teaching_plans_created = Audited.audit_class.as_user(user) do
        CopyDisciplineTeachingPlanService.call(
          discipline_teaching_plan_id,
          year,
          unities_ids,
          grades_ids,
          created_by_administrator: user.has_administrator_access_level?
        )
      end

      SystemNotificationCreator.create!(
        source: discipline_teaching_plans_created.first,
        title: I18n.t('copy_discipline_teaching_plan_worker.title'),
        description: I18n.t('copy_discipline_teaching_plan_worker.description'),
        users: [user]
      )
    end
  end
end
