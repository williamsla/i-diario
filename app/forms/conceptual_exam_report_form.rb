# frozen_string_literal: true

class ConceptualExamReportForm
  include ActiveModel::Model

  attr_accessor :unity_id, :classroom_id, :step_id

  validates :unity_id, presence: true
  validates :classroom_id, presence: true
  validates :step_id, presence: true

  def classroom
    @classroom ||= Classroom.find_by(id: classroom_id)
  end

  def step
    return if step_id.blank? || classroom.blank?

    @step ||= StepsFetcher.new(classroom).step_by_id(step_id)
  end
end
