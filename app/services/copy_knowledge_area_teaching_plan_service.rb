class CopyKnowledgeAreaTeachingPlanService
  class CopyKnowledgeAreaTeachingPlanError < StandardError; end

  attr_reader :knowledge_area_teaching_plan_id, :year, :unities_ids, :grades_ids, :created_by_administrator

  def self.call(*params)
    new(*params).call
  end

  def initialize(
    knowledge_area_teaching_plan_id,
    year,
    unities_ids,
    grades_ids,
    created_by_administrator: false
  )
    @knowledge_area_teaching_plan_id = knowledge_area_teaching_plan_id
    @year = year
    @unities_ids = unities_ids
    @grades_ids = grades_ids
    @created_by_administrator = created_by_administrator

    check_required_params
  end

  def call
    model = KnowledgeAreaTeachingPlan.find(knowledge_area_teaching_plan_id)
    model_teaching_plan = model.teaching_plan
    knowledge_area_ids = model.knowledge_area_ids.split(',')
    experience_fields = model.experience_fields

    fetch_contents_and_objectives(model_teaching_plan)

    if copy_as_unificado?(model_teaching_plan)
      copy_unificado_plans(model_teaching_plan, knowledge_area_ids, experience_fields)
    else
      copy_by_teacher(model_teaching_plan, knowledge_area_ids, experience_fields)
    end
  end

  private

  def copy_as_unificado?(_teaching_plan)
    created_by_administrator
  end

  def fetch_contents_and_objectives(teaching_plan)
    @content_ids = teaching_plan.contents_teaching_plans.map.with_index do |content_teaching_plan, index|
      @contents_created_at_position ||= {}
      @contents_created_at_position[content_teaching_plan.content_id] = index
      content_teaching_plan.content_id
    end

    @objective_ids = teaching_plan.objectives_teaching_plans.map.with_index do |objective_teaching_plan, index|
      @objectives_created_at_position ||= {}
      @objectives_created_at_position[objective_teaching_plan.objective_id] = index
      objective_teaching_plan.objective_id
    end
  end

  def copy_unificado_plans(teaching_plan, knowledge_area_ids, experience_fields)
    new_plans = []

    unities_ids.each do |unity_id|
      grades_ids.each do |grade_id|
        next if Classroom.by_unity(unity_id).by_grade(grade_id).none?
        next if unificado_copy_exists?(teaching_plan, knowledge_area_ids, unity_id, grade_id)

        new_plans << create_copy(
          teaching_plan,
          knowledge_area_ids,
          experience_fields,
          nil,
          grade_id,
          unity_id
        )
      end
    end

    new_plans
  end

  def unificado_copy_exists?(teaching_plan, knowledge_area_ids, unity_id, grade_id)
    KnowledgeAreaTeachingPlan
      .by_unity(unity_id)
      .by_grade(grade_id)
      .by_year(year)
      .by_secretary
      .by_knowledge_area(knowledge_area_ids)
      .joins(:teaching_plan)
      .where(
        teaching_plans: {
          school_term_type_id: teaching_plan.school_term_type_id,
          school_term_type_step_id: teaching_plan.school_term_type_step_id
        }
      )
      .exists?
  end

  def copy_by_teacher(teaching_plan, knowledge_area_ids, experience_fields)
    new_plans = []
    copies_done = {}

    unities_ids.each do |unity_id|
      copies_done[unity_id] = {}

      grades_ids.each do |grade_id|
        copies_done[unity_id][grade_id] = {}

        classrooms_in_grade = Classroom.by_unity(unity_id).by_grade(grade_id).pluck(:id)
        next if classrooms_in_grade.blank?

        teacher_disciplines_classrooms = TeacherDisciplineClassroom
          .includes(:teacher)
          .by_knowledge_area_id(knowledge_area_ids)
          .where(year: year, classroom_id: classrooms_in_grade)

        teacher_disciplines_classrooms.each do |teacher_discipline_classroom|
          teacher = teacher_discipline_classroom.teacher
          next unless teacher

          copies_done[unity_id][grade_id][teacher.id] ||= []
          knowledge_area_ids_to_save = (knowledge_area_ids - copies_done[unity_id][grade_id][teacher.id]).uniq
          next if knowledge_area_ids_to_save.empty?

          copies_done[unity_id][grade_id][teacher.id] += knowledge_area_ids_to_save

          new_plans << create_copy(
            teaching_plan,
            knowledge_area_ids_to_save,
            experience_fields,
            teacher,
            grade_id,
            unity_id
          )
        end
      end
    end

    new_plans
  end

  def create_copy(teaching_plan, knowledge_area_ids, experience_fields, teacher, grade_id, unity_id)
    copy = teaching_plan.dup
    copy.unity_id = unity_id
    copy.grade_id = grade_id
    copy.year = year
    copy.contents_created_at_position = @contents_created_at_position
    copy.objectives_created_at_position = @objectives_created_at_position
    copy.content_ids = @content_ids
    copy.objective_ids = @objective_ids
    copy.teacher = teacher

    copy.build_knowledge_area_teaching_plan(experience_fields: experience_fields)
    copy.save!(validate: false)

    copy.knowledge_area_teaching_plan.knowledge_area_ids = knowledge_area_ids
    copy.knowledge_area_teaching_plan.save!(validate: false)
    copy.knowledge_area_teaching_plan
  end

  def check_required_params
    required_params_missing = unities_ids.blank? ||
                              grades_ids.blank? ||
                              knowledge_area_teaching_plan_id.blank? ||
                              year.blank?

    raise CopyKnowledgeAreaTeachingPlanError, 'Missing required parameters' if required_params_missing
  end
end
