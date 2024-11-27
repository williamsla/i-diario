class DiaryReport < BaseReport
    def self.build(entity_configuration, date_start, date_end, discipline_lesson_plan, current_teacher)
      new.build(entity_configuration, date_start, date_end, discipline_lesson_plan, current_teacher)
    end
  
    def build(entity_configuration, date_start, date_end, discipline_lesson_plan, current_teacher)
      @entity_configuration = entity_configuration
      @date_start = date_start
      @date_end = date_end
      @discipline_lesson_plans = discipline_lesson_plan
      @current_teacher = current_teacher
       
      self
    end
  
    private
  
  
  end
  