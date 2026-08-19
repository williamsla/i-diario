class PlanAuthorFetcher
  def initialize(component, current_teacher)
    @component = component
    @current_teacher = current_teacher
  end

  def author
    return I18n.t('enumerations.plans_authors.my_plans') if unificado? || my_plans?

    I18n.t('enumerations.plans_authors.others')
  end

  private

  def unificado?
    @component.try(:semed?)
  end

  def my_plans?
    teacher = @component.try(:teacher)
    teacher.present? && teacher.id == @current_teacher.try(:id)
  end
end
