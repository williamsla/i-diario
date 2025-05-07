class UserForTeacherUpdaterWorker
  include Sidekiq::Worker

  sidekiq_options unique: :until_and_while_executing, queue: :low

  def perform(entity_id, teacher_id, cpf, school_id)
    Entity.find(entity_id).using_connection do
      UserForTeacherUpdater.create!(teacher_id, cpf, school_id)
    end
  end
end
