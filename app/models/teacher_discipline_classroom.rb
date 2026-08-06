class TeacherDisciplineClassroom < ApplicationRecord
  include Audit
  include Discardable

  acts_as_copy_target

  audited

  belongs_to :teacher
  belongs_to :discipline
  belongs_to :classroom
  belongs_to :grade

  delegate :knowledge_area, to: :discipline

  has_many :student_enrollment_classrooms, through: :classroom

  has_enumeration_for :period, with: Periods, skip_validation: true

  validates :teacher, :teacher_api_code, :discipline_api_code, :classroom_api_code, :year, presence: true

  default_scope { where(active: true).kept }

  scope :by_classroom, ->(classroom) { where(classroom: classroom) }
  scope :by_score_type, ->(score_type) { where(score_type: score_type) }
  scope :by_teacher_id, ->(teacher_id) { where(teacher_id: teacher_id) }
  scope :by_discipline_id, ->(discipline_id) { where(discipline_id: discipline_id) }
  scope :by_grade_id, ->(grade_id) { where(grade_id: grade_id) }
  scope :by_year, ->(year) { where(year: year) }
  scope :by_period, ->(period) { where(period: period) }
  scope :by_knowledge_area_id, ->(knowledge_area_id) {
    joins(:discipline).where(disciplines: { knowledge_area_id: knowledge_area_id })
  }

  def left_at
    [end_at, allocation_left_at].compact.min
  end

  def left?
    left_at.present? && left_at <= Date.current
  end

  def self.left_at_for(teacher_id:, classroom_id:)
    where(classroom_id: classroom_id, teacher_id: teacher_id)
      .where('end_at IS NOT NULL OR allocation_left_at IS NOT NULL')
      .pluck(:end_at, :allocation_left_at)
      .map { |end_at, allocation_left_at| [end_at, allocation_left_at].compact.min }
      .compact
      .min
  end
end
