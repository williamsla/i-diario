class DiaryReportForm
    include ActiveModel::Model
  
    attr_accessor :unity_id,
                  :classroom_id,
                  :school_calendar_year,                  
                  :discipline_id,
                  :teacher_id,
                  :start_at,
                  :end_at,
                  :receive_email_confirmation
  
    validates :unity_id, presence: true
    validates :classroom_id, presence: true

    def receive_email_confirmation_as_boolean
        ActiveRecord::Type::Boolean.new.cast(
            receive_email_confirmation
        )
    end
    private

end
  