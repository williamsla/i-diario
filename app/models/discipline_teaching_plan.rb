class DisciplineTeachingPlan < ApplicationRecord
  include Audit
  include ColumnsLockable
  include TeacherRelationable
  include Translatable

  not_updatable only: :discipline_id
  teacher_relation_columns only: :discipline

  audited
  has_associated_audits

  acts_as_copy_target

  belongs_to :teaching_plan, dependent: :destroy
  belongs_to :discipline

  delegate :contents, to: :teaching_plan
  delegate :objectives, to: :teaching_plan

  accepts_nested_attributes_for :teaching_plan

  scope :by_year, ->(year) { joins(:teaching_plan).where(teaching_plans: { year: year }) }
  scope :by_unity, ->(unity) { joins(:teaching_plan).where(teaching_plans: { unity_id: unity }) }
  scope :by_grade, ->(grade) { joins(:teaching_plan).where(teaching_plans: { grade_id: grade }) }
  scope :by_school_term_type_id, lambda { |school_term_type_id|
    joins(:teaching_plan).where(teaching_plans: { school_term_type_id: school_term_type_id })
  }
  scope :by_school_term_type_step_id, lambda { |school_term_type_step_id|
    joins(:teaching_plan).where(teaching_plans: { school_term_type_step_id: school_term_type_step_id })
  }
  scope :by_discipline, ->(discipline) { where(discipline: discipline) }
  scope :by_teacher_id, ->(teacher_id) { joins(:teaching_plan).where(teaching_plans: { teacher_id: teacher_id }) }
  scope :by_student_id, lambda { |student_id|
    if student_id.to_i > 0
      joins(:teaching_plan).where(teaching_plans: { student_id: student_id })
    else 
      joins(:teaching_plan).where('teaching_plans.student_id IS NULL')
    end
  }
  scope :by_other_teacher_id, lambda { |teacher_id|
    joins(:teaching_plan).where.not(teaching_plans: { teacher_id: [teacher_id, nil] })
  }
  scope :by_secretary, -> { joins(:teaching_plan).where(teaching_plans: { teacher_id: nil }) }
  scope :by_author, lambda { |author_type, current_teacher_id|
    teacher_id = current_teacher_id.respond_to?(:id) ? current_teacher_id.try(:id) : current_teacher_id
    unificado_condition = <<~SQL.squish
      teaching_plans.teacher_id IS NULL
      OR teaching_plans.id IN (#{TeachingPlan.administrator_created_ids_sql})
    SQL

    case author_type.to_s
    when PlansAuthors::MY_PLANS.to_s
      if teacher_id.present?
        joins(:teaching_plan).where(
          "teaching_plans.teacher_id = :teacher_id OR #{unificado_condition}",
          teacher_id: teacher_id
        )
      else
        joins(:teaching_plan).where(unificado_condition)
      end
    when PlansAuthors::ALL.to_s, '', 'empty'
      all
    else
      if teacher_id.present?
        joins(:teaching_plan).where(
          "teaching_plans.teacher_id IS NOT NULL
           AND teaching_plans.teacher_id != :teacher_id
           AND NOT (#{unificado_condition})",
          teacher_id: teacher_id
        )
      else
        joins(:teaching_plan).where(
          "teaching_plans.teacher_id IS NOT NULL AND NOT (#{unificado_condition})"
        )
      end
    end
  }
  scope :order_by_school_term_type_step, lambda {
    joins(:teaching_plan).order('teaching_plans.school_term_type_step_id IS NULL')
  }
  scope :order_by_grades, -> { joins(teaching_plan: :grade).order(Grade.arel_table[:description].desc) }

  validates :teaching_plan, presence: true
  validates :discipline, presence: true

  def optional_teacher
    true
  end
end
