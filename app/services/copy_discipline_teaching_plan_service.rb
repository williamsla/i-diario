class CopyDisciplineTeachingPlanService
  class CopyDisciplineTeachingPlanError < StandardError; end
  attr_reader :discipline_teaching_plan_id, :year, :unities_ids, :grades_ids, :created_by_administrator, :empty_reasons

  def self.call(*params)
    new(*params).call
  end

  def initialize(
    discipline_teaching_plan_id,
    year,
    unities_ids,
    grades_ids,
    created_by_administrator: false
  )
    @discipline_teaching_plan_id = discipline_teaching_plan_id
    @year = year
    @unities_ids = unities_ids
    @grades_ids = grades_ids
    @created_by_administrator = created_by_administrator
    @empty_reasons = []

    check_required_params
  end

  def call
    model_discipline_teaching_plan = DisciplineTeachingPlan.find(discipline_teaching_plan_id)
    model_teaching_plan = model_discipline_teaching_plan.teaching_plan
    discipline_id = model_discipline_teaching_plan.discipline_id
    thematic_unit = model_discipline_teaching_plan.thematic_unit

    fetch_contents_and_objectives(model_teaching_plan)

    if copy_as_unificado?(model_teaching_plan)
      copy_unificado_plans(model_teaching_plan, discipline_id, thematic_unit)
    else
      fetch_teacher_discipline_classrooms(model_teaching_plan, discipline_id, thematic_unit)
    end
  end

  private

  def copy_as_unificado?(_teaching_plan)
    created_by_administrator
  end

  def fetch_contents_and_objectives(teaching_plan)
    objectives = teaching_plan.objectives_teaching_plans
    contents = teaching_plan.contents_teaching_plans

    @content_ids = contents.map.with_index do |content_teaching_plan, index|
      @contents_created_at_position ||= {}
      @contents_created_at_position[content_teaching_plan.content_id] = index
      content_teaching_plan.content_id
    end

    @objective_ids = objectives.map.with_index do |objective_teaching_plan, index|
      @objectives_created_at_position ||= {}
      @objectives_created_at_position[objective_teaching_plan.objective_id] = index
      objective_teaching_plan.objective_id
    end
  end

  def copy_unificado_plans(teaching_plan, discipline_id, thematic_unit)
    new_discipline_teaching_plans = []

    unities_ids.each do |unity_id|
      grades_ids.each do |grade_id|
        destination_grade_id, classroom_ids = destination_grade_and_classrooms(unity_id, grade_id)

        if classroom_ids.blank?
          empty_reasons << :no_classroom
          next
        end

        if unificado_copy_exists?(teaching_plan, discipline_id, unity_id, destination_grade_id, thematic_unit)
          empty_reasons << :already_exists
          next
        end

        new_discipline_teaching_plans << create_copies_discipline_teaching_plans(
          teaching_plan,
          discipline_id,
          nil,
          destination_grade_id,
          unity_id,
          thematic_unit
        )
      end
    end

    new_discipline_teaching_plans
  end

  def empty_reason
    reasons = empty_reasons.uniq
    return :already_exists if reasons == [:already_exists]
    return :no_classroom if reasons == [:no_classroom]

    :empty
  end

  def unificado_copy_exists?(teaching_plan, discipline_id, unity_id, grade_id, thematic_unit)
    DisciplineTeachingPlan
      .joins(:teaching_plan)
      .where(discipline_id: discipline_id)
      .where(
        teaching_plans: {
          unity_id: unity_id,
          grade_id: grade_id,
          year: year,
          teacher_id: nil,
          school_term_type_id: teaching_plan.school_term_type_id,
          school_term_type_step_id: teaching_plan.school_term_type_step_id
        }
      )
      .where(
        "COALESCE(discipline_teaching_plans.thematic_unit, '') = ?",
        thematic_unit.to_s
      )
      .exists?
  end

  def destination_grade_and_classrooms(unity_id, grade_id)
    exact_ids = Classroom.by_unity(unity_id).by_grade(grade_id).distinct.pluck('classrooms.id')
    return [grade_id, exact_ids] if exact_ids.present?

    grade = Grade.find_by(id: grade_id)
    return [grade_id, []] unless grade

    classroom_ids = Classroom.by_unity(unity_id)
      .joins(classrooms_grades: :grade)
      .where(grades: { description: grade.description, course_id: grade.course_id })
      .distinct
      .pluck('classrooms.id')
    return [grade_id, []] if classroom_ids.blank?

    linked_grade_id = ClassroomsGrade.where(classroom_id: classroom_ids)
      .joins(:grade)
      .where(grades: { description: grade.description, course_id: grade.course_id })
      .limit(1)
      .pluck(:grade_id)
      .first

    [linked_grade_id || grade_id, classroom_ids]
  end

  def fetch_teacher_discipline_classrooms(teaching_plan, discipline_id, thematic_unit)
    new_discipline_teaching_plans = []

    unities_ids.each do |unity_id|
      classroom_ids = Classroom.by_unity(unity_id).by_grade(grades_ids).pluck(:id)

      next if classroom_ids.blank?

      teacher_disciplines_classrooms = TeacherDisciplineClassroom
        .includes(:teacher)
        .where(
          year: year,
          discipline_id: discipline_id,
          classroom_id: classroom_ids,
          grade_id: grades_ids
        )
        .group_by(&:grade_id)
        .flat_map { |_key, value| value.group_by(&:teacher_id).map { |_key, value| value.first } }

      teacher_disciplines_classrooms.each do |teacher_discipline_classroom|
        teacher = teacher_discipline_classroom.teacher
        grade_id = teacher_discipline_classroom.grade_id

        next unless teacher

        new_discipline_teaching_plans << create_copies_discipline_teaching_plans(
          teaching_plan,
          discipline_id,
          teacher,
          grade_id,
          unity_id,
          thematic_unit
        )
      end
    end

    new_discipline_teaching_plans
  end

  def create_copies_discipline_teaching_plans(
    teaching_plan,
    discipline_id,
    teacher,
    grade_id,
    unity_id,
    thematic_unit
  )
    copy_teaching_plan = teaching_plan.dup
    copy_teaching_plan.unificado = created_by_administrator
    copy_teaching_plan.unity_id = unity_id
    copy_teaching_plan.grade_id = grade_id
    copy_teaching_plan.year = year
    copy_teaching_plan.contents_created_at_position = @contents_created_at_position
    copy_teaching_plan.objectives_created_at_position = @objectives_created_at_position
    copy_teaching_plan.content_ids = @content_ids
    copy_teaching_plan.objective_ids = @objective_ids
    copy_teaching_plan.teacher = teacher

    copy_teaching_plan.build_discipline_teaching_plan(
      discipline_id: discipline_id,
      thematic_unit: thematic_unit
    )

    error_message = "Erro ao salvar o plano de ensino: #{copy_teaching_plan.errors.full_messages}"

    raise CopyDisciplineTeachingPlanError, error_message unless copy_teaching_plan.valid?

    copy_teaching_plan.save!
    copy_teaching_plan.discipline_teaching_plan
  end

  def check_required_params
    required_params_missing = unities_ids.blank? ||
                              grades_ids.blank? ||
                              discipline_teaching_plan_id.blank? ||
                              year.blank?

    raise CopyDisciplineTeachingPlanError, 'Missing required parameters' if required_params_missing
  end
end
