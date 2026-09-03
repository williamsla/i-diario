class TeachingPlan < ApplicationRecord
  include Audit
  include TeacherRelationable
  include Translatable

  teacher_relation_columns only: :grades

  audited except: [:old_contents]
  has_associated_audits
  acts_as_copy_target

  belongs_to :unity
  belongs_to :grade
  belongs_to :teacher
  belongs_to :school_term_type
  belongs_to :school_term_type_step
  belongs_to :student, optional: true


  validates :year, presence: true
  validates :unity, presence: true
  validates :grade, presence: true
  validates :school_term_type, presence: true
  validates :school_term_type_step, presence: { unless: :yearly? }

  has_many :contents_teaching_plans, dependent: :destroy
  deferred_has_many :contents, through: :contents_teaching_plans
  has_many :objectives_teaching_plans, dependent: :destroy
  deferred_has_many :objectives, through: :objectives_teaching_plans
  has_many :teaching_plan_attachments, dependent: :destroy

  has_one :discipline_teaching_plan, dependent: :restrict_with_error
  has_one :knowledge_area_teaching_plan, dependent: :restrict_with_error

  accepts_nested_attributes_for :contents, allow_destroy: true
  accepts_nested_attributes_for :objectives, allow_destroy: true
  accepts_nested_attributes_for :teaching_plan_attachments, allow_destroy: true

  validate :at_least_one_content_assigned

  scope :by_unity_id, ->(unity_id) { where(unity_id: unity_id) }
  scope :by_teacher_id, ->(teacher_id) { where(teacher_id: teacher_id) }
  scope :by_year, ->(year) { where(year: year) }
  scope :semed, -> { where(teacher_id: nil) }
  scope :unificado, lambda {
    where(
      "#{table_name}.teacher_id IS NULL OR " \
      "#{table_name}.id IN (#{administrator_created_ids_sql})"
    )
  }

  attr_accessor :grade_ids, :contents_created_at_position, :objectives_created_at_position

  def self.administrator_created_ids_sql
    Audited::Audit
      .joins("INNER JOIN users ON users.id = audits.user_id AND audits.user_type = 'User'")
      .joins('INNER JOIN user_roles ON user_roles.id = users.current_user_role_id')
      .joins('INNER JOIN roles ON roles.id = user_roles.role_id')
      .where(auditable_type: name, action: 'create')
      .where(roles: { access_level: AccessLevel::ADMINISTRATOR })
      .select('audits.auditable_id')
      .to_sql
  end

  def semed?
    unificado?
  end

  def unificado?
    self[:teacher_id].nil? || created_by_administrator?
  end

  def created_by_administrator?
    creation_user&.administrator?
  end

  def creation_user
    creation_audit&.user
  end

  def creation_audit
    create_audits = if association(:audits).loaded?
                      audits.select { |audit| audit.action == 'create' }
                    else
                      audits.where(action: 'create').to_a
                    end

    create_audits.min_by(&:id)
  end

  def to_s
    return discipline_teaching_plan.discipline.to_s if discipline_teaching_plan
    return knowledge_area_teaching_plan.knowledge_areas.ordered.first.to_s if knowledge_area_teaching_plan
  end

  def contents_tags
    if @contents_tags.present?
      ContentTagConverter.tags_to_json(@contents_tags)
    else
      ContentTagConverter.contents_to_json(contents_ordered)
    end
  end

  def contents_ordered
    contents.order('contents_teaching_plans.position')
  end

  def objectives_ordered
    objectives.order('objectives_teaching_plans.position')
  end

  def school_term_type_step_humanize
    return '' if yearly?

    school_term_type_step.to_s
  end

  def optional_teacher
    true
  end

  def attachments?
    teaching_plan_attachments.any?
  end

  def yearly?
    return unless school_term_type

    SchoolTermType.where("description ILIKE 'Anual%'").where(id: school_term_type.id)
  end

  private

  def at_least_one_content_assigned
    return unless contents_empty?

    errors.add(:contents, :at_least_one_content_assigned)
  end

  def contents_empty?
    contents.empty? || (contents.size == contents.select(&:marked_for_destruction?).size)
  end
end
