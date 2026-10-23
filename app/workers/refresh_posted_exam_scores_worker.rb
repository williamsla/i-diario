class RefreshPostedExamScoresWorker
  include Sidekiq::Worker

  sidekiq_options queue: :low, retry: 3

  def perform(entity_id, snapshot)
    Entity.find(entity_id).using_connection do
      PostedExamScoreRefresher.new(snapshot).call
    end
  end
end