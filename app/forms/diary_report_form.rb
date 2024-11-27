class DiaryReportForm
    include ActiveModel::Model
  
    attr_accessor :unity_id,
                  :classroom_id,
                  :school_calendar_year,                  
                  :discipline_id,
                  :teacher_id,
                  :start_at,
                  :end_at
  
    validates :unity_id, presence: true
    validates :classroom_id, presence: true

    private

end
  