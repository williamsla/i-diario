# frozen_string_literal: true

class ConceptualExamBatchForm
  include ActiveModel::Model

  attr_accessor :unity_id, :classroom_id, :step_id, :recorded_at, :students, :teacher_id, :current_user

  validates :unity_id, presence: true
  validates :classroom_id, presence: true
  validates :step_id, presence: true
  # recorded_at é definido internamente como última data da etapa (não é informado pelo usuário)

  def initialize(attributes = {})
    @students = attributes.delete(:students) || {}
    @teacher_id = attributes.delete(:teacher_id)
    @current_user = attributes.delete(:current_user)
    super(attributes)
  end

  def students_attributes=(hash)
    return if hash.blank?

    @students = hash.to_unsafe_h if hash.respond_to?(:to_unsafe_h)
    @students = hash.with_indifferent_access if hash.is_a?(Hash)
  end

  def classroom
    @classroom ||= Classroom.find_by(id: classroom_id)
  end

  def step
    return if step_id.blank? || classroom.blank?

    @step ||= StepsFetcher.new(classroom).step_by_id(step_id)
  end

  def unity
    @unity ||= Unity.find_by(id: unity_id)
  end
end
