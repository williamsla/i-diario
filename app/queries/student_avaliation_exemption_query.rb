class StudentAvaliationExemptionQuery
  def initialize(student)
    @student = student
  end

  def is_exempted(avaliation)
    exempted_avaliation_ids.include?(avaliation.id)
  end

  private

  attr_accessor :student

  def exempted_avaliation_ids
    @exempted_avaliation_ids ||= ReportQueryCache.fetch([:avaliation_exemptions, student.id]) do
      AvaliationExemption.by_student(student).pluck(:avaliation_id)
    end
  end
end
