class ContentsRecordFetcher
  def fetch
    # Verifica se existe algum plano de aula (do mesmo professor ou de outro)
    same_teacher_plans_exist = same_teacher_lesson_plans.exists?
    other_teacher_plans_exist = other_teacher_lesson_plans.exists?
    has_lesson_plan = same_teacher_plans_exist || other_teacher_plans_exist

    if has_lesson_plan
      # Se existe plano de aula, retorna apenas conteúdos dos planos de aula
      # Não inclui conteúdos do plano de ensino
      plans = same_teacher_lesson_plans.presence || other_teacher_lesson_plans.presence || []
    else
      # Se não existe plano de aula, busca planos de ensino
      plans = same_teacher_teaching_plans.presence ||
              same_teacher_yearly_teaching_plans.presence ||
              unificado_teaching_plans.presence ||
              unificado_yearly_teaching_plans.presence ||
              other_teacher_teaching_plans.presence ||
              []
    end

    items_from_plans(plans, :contents)
  end

  def fetch_objectives
    # Verifica se existe algum plano de aula (do mesmo professor ou de outro)
    has_lesson_plan = same_teacher_lesson_plans_objectives.exists? || other_teacher_lesson_plans_objectives.exists?

    if has_lesson_plan
      # Se existe plano de aula, retorna apenas objetivos dos planos de aula
      # Não inclui objetivos do plano de ensino
      plans = same_teacher_lesson_plans_objectives.presence || other_teacher_lesson_plans_objectives.presence || []
    else
      # Se não existe plano de aula, busca planos de ensino
      plans = same_teacher_teaching_plans.presence ||
              same_teacher_yearly_teaching_plans.presence ||
              unificado_teaching_plans.presence ||
              unificado_yearly_teaching_plans.presence ||
              other_teacher_teaching_plans.presence ||
              []
    end

    items_from_plans(plans, :objectives)
  end

  protected

  def items_from_plans(plans, association)
    items_by_id = {}

    Array(plans).each do |plan|
      experience_fields = plan.try(:experience_fields).presence

      Array(plan.public_send(association)).each do |item|
        existing = items_by_id[item.id]

        if existing
          merge_experience_fields!(existing, experience_fields)
        else
          item.experience_fields = experience_fields if item.respond_to?(:experience_fields=)
          items_by_id[item.id] = item
        end
      end
    end

    items_by_id.values
  end

  def merge_experience_fields!(item, experience_fields)
    return if experience_fields.blank? || !item.respond_to?(:experience_fields=)

    current = item.experience_fields.to_s.split(', ').reject(&:blank?)
    return if current.include?(experience_fields)

    item.experience_fields = (current + [experience_fields]).join(', ')
  end


  def same_teacher_lesson_plans
    lesson_plans.by_teacher_id(@teacher.id)
  end

  def same_teacher_lesson_plans_objectives
    lesson_plans_objectives.by_teacher_id(@teacher.id)
  end

  def same_teacher_teaching_plans
    teaching_plans.by_teacher_id(@teacher.id)
                  .by_school_term_type_step_id(school_term_type_steps_ids)
  end

  def same_teacher_yearly_teaching_plans
    teaching_plans.by_teacher_id(@teacher.id)
                  .by_school_term_type_id(yearly_school_term_type_id)
  end

  def unificado_teaching_plans
    teaching_plans.unificado
                  .by_school_term_type_step_id(school_term_type_steps_ids)
  end

  def unificado_yearly_teaching_plans
    teaching_plans.unificado
                  .by_school_term_type_id(yearly_school_term_type_id)
  end

  def other_teacher_lesson_plans
    lesson_plans.by_other_teacher_id(@teacher.id)
  end

  def other_teacher_lesson_plans_objectives
    lesson_plans_objectives.by_other_teacher_id(@teacher.id)
  end

  def other_teacher_teaching_plans
    teaching_plans.by_other_teacher_id(@teacher.id)
  end

  def steps_fetcher
    @steps_fetcher ||= StepsFetcher.new(@classroom)
  end

  def school_calendar_year
    steps_fetcher.school_calendar.try(:year) || @date.to_date.year
  end

  def school_term_type_steps_ids
    return [] unless (step = steps_fetcher.step_by_date(@date.to_date))

    steps_number = step.school_calendar_parent.steps.size
    description = step.school_calendar_parent.step_type_description

    SchoolTermTypeStep.joins(:school_term_type)
                      .where(step_number: step.step_number)
                      .where(
                        school_term_types: {
                          steps_number: steps_number,
                          description: "#{description} (#{steps_number} #{'etapa'.pluralize(steps_number)})"
                        }
                      )
                      .pluck(:id)
  end

  def yearly_school_term_type_id
    SchoolTermType.where("description = ? OR description = ?", 'Anual', 'Anual (1 etapa)').pluck(:id)
  end
end
