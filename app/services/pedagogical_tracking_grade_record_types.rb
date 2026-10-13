class PedagogicalTrackingGradeRecordTypes
  DISCIPLINE = 'discipline'.freeze
  KNOWLEDGE_AREA = 'knowledge_area'.freeze
  BOTH = 'both'.freeze
  NONE = 'none'.freeze

  def initialize(year:, grade_ids:, unity_ids: nil)
    @year = year
    @grade_ids = Array(grade_ids).map(&:to_i).uniq
    @unity_ids = Array(unity_ids).presence
  end

  def call
    return {} if @grade_ids.blank?

    discipline_grades = grade_ids_for(:discipline_content_record)
    knowledge_area_grades = grade_ids_for(:knowledge_area_content_record)

    @grade_ids.each_with_object({}) do |grade_id, memo|
      has_discipline = discipline_grades.include?(grade_id)
      has_knowledge_area = knowledge_area_grades.include?(grade_id)

      memo[grade_id] = if has_discipline && has_knowledge_area
                         BOTH
                       elsif has_knowledge_area
                         KNOWLEDGE_AREA
                       elsif has_discipline
                         DISCIPLINE
                       else
                         NONE
                       end
    end
  end

  private

  def grade_ids_for(association)
    scope = ContentRecord
      .joins(association)
      .joins(classroom: :classrooms_grades)
      .where(classrooms: { year: @year })
      .where(classrooms_grades: { grade_id: @grade_ids })

    scope = scope.where(classrooms: { unity_id: @unity_ids }) if @unity_ids

    scope.distinct.pluck('classrooms_grades.grade_id').map(&:to_i)
  end
end
