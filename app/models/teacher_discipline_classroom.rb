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
    exits = []
    exits << end_at if end_at.present?
    exits << allocation_left_at if allocation_exit_applies?
    exits.min
  end

  def left?(on: Date.current)
    exit_on = left_at
    exit_on.present? && exit_on <= on
  end

  def current?(on: Date.current)
    (start_at.blank? || start_at <= on) && !left?(on: on)
  end

  # A saída da alocação anterior não encerra o vínculo que começou depois dela.
  def allocation_exit_applies?
    allocation_left_at.present? && (start_at.blank? || start_at <= allocation_left_at)
  end

  def self.left_at_for(teacher_id:, classroom_id:, on: Date.current)
    links = where(classroom_id: classroom_id, teacher_id: teacher_id).to_a
    return if links.any? { |link| link.current?(on: on) }

    links.map(&:left_at).compact.select { |date| date <= on }.max
  end
end
