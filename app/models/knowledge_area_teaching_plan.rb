class KnowledgeAreaTeachingPlan < ApplicationRecord
  include Audit
  include TeacherRelationable
  include Translatable

  teacher_relation_columns only: :knowledge_areas

  acts_as_copy_target

  audited
  has_associated_audits

  belongs_to :teaching_plan, dependent: :destroy
  has_many :knowledge_area_teaching_plan_knowledge_areas, dependent: :destroy
  has_many :knowledge_areas, through: :knowledge_area_teaching_plan_knowledge_areas

  delegate :contents, to: :teaching_plan
  delegate :objectives, to: :teaching_plan

  accepts_nested_attributes_for :teaching_plan

  scope :by_year, ->(year) { joins(:teaching_plan).where(teaching_plans: { year: year }) }
  scope :by_unity, ->(unity) { joins(:teaching_plan).where(teaching_plans: { unity_id: unity }) }
  scope :by_unity_or_unificado, lambda { |unity|
    unity_id = unity.respond_to?(:id) ? unity.id : unity
    joins(:teaching_plan).where(
      'teaching_plans.unity_id = :unity_id OR teaching_plans.unificado = TRUE',
      unity_id: unity_id
    )
  }
  scope :by_grade, ->(grade) { joins(:teaching_plan).where(teaching_plans: { grade_id: grade }) }
  scope :by_school_term_type_id, lambda { |school_term_type_id|
    joins(:teaching_plan).where(teaching_plans: { school_term_type_id: school_term_type_id })
  }
  scope :by_school_term_type_step_id, lambda { |school_term_type_step_id|
    joins(:teaching_plan).where(teaching_plans: { school_term_type_step_id: school_term_type_step_id })
  }
  scope :by_knowledge_area, ->(knowledge_area) { by_knowledge_area(knowledge_area) }
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
  scope :unificado, -> { joins(:teaching_plan).merge(TeachingPlan.unificado) }
  scope :by_author, lambda { |author_type, current_teacher_id|
    teacher_id = current_teacher_id.respond_to?(:id) ? current_teacher_id.try(:id) : current_teacher_id
    unificado_condition = unificado_sql_condition

    case author_type.to_s
    when PlansAuthors::MY_PLANS.to_s
      if teacher_id.present?
        joins(:teaching_plan).where(
          <<~SQL.squish,
            (
              teaching_plans.teacher_id = :teacher_id
              AND NOT (#{unificado_condition})
            )
            OR knowledge_area_teaching_plans.id IN (#{deduped_unificado_ids_sql})
          SQL
          teacher_id: teacher_id
        )
      else
        joins(:teaching_plan).where(
          "knowledge_area_teaching_plans.id IN (#{deduped_unificado_ids_sql})"
        )
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

  scope :order_by_grades, lambda {
    joins(teaching_plan: :grade).order(Grade.arel_table[:description].desc)
  }

  validates :teaching_plan, presence: true
  validates :knowledge_area_ids, presence: true

  def self.unificado_sql_condition
    "teaching_plans.unificado = TRUE OR teaching_plans.teacher_id IS NULL OR " \
    "teaching_plans.id IN (#{TeachingPlan.unificado_created_ids_sql})"
  end

  def self.deduped_unificado_ids_sql
    <<~SQL.squish
      SELECT DISTINCT ON (
        teaching_plans.unity_id,
        teaching_plans.grade_id,
        teaching_plans.school_term_type_id,
        teaching_plans.school_term_type_step_id,
        teaching_plans.year,
        COALESCE(knowledge_area_teaching_plans.experience_fields, ''),
        (
          SELECT string_agg(katpka.knowledge_area_id::text, ',' ORDER BY katpka.knowledge_area_id)
          FROM knowledge_area_teaching_plan_knowledge_areas katpka
          WHERE katpka.knowledge_area_teaching_plan_id = knowledge_area_teaching_plans.id
        )
      ) knowledge_area_teaching_plans.id
      FROM knowledge_area_teaching_plans
      INNER JOIN teaching_plans
        ON teaching_plans.id = knowledge_area_teaching_plans.teaching_plan_id
      WHERE #{unificado_sql_condition}
      ORDER BY
        teaching_plans.unity_id,
        teaching_plans.grade_id,
        teaching_plans.school_term_type_id,
        teaching_plans.school_term_type_step_id,
        teaching_plans.year,
        COALESCE(knowledge_area_teaching_plans.experience_fields, ''),
        (
          SELECT string_agg(katpka.knowledge_area_id::text, ',' ORDER BY katpka.knowledge_area_id)
          FROM knowledge_area_teaching_plan_knowledge_areas katpka
          WHERE katpka.knowledge_area_teaching_plan_id = knowledge_area_teaching_plans.id
        ),
        CASE WHEN teaching_plans.teacher_id IS NULL THEN 0 ELSE 1 END,
        knowledge_area_teaching_plans.id ASC
    SQL
  end

  def optional_teacher
    true
  end

  def knowledge_area_ids
    knowledge_areas.collect(&:id).join(',')
  end

  private

  def self.by_teacher(teacher)
    joins(:teaching_plan).joins(:knowledge_area_teaching_plan_knowledge_areas)
      .joins(
        arel_table.join(Discipline.arel_table, Arel::Nodes::OuterJoin)
          .on(
            Discipline.arel_table[:knowledge_area_id]
              .eq(KnowledgeAreaTeachingPlanKnowledgeArea.arel_table[:knowledge_area_id])
          )
          .join_sources
      )
      .joins(
        arel_table.join(TeacherDisciplineClassroom.arel_table, Arel::Nodes::OuterJoin)
          .on(
            TeacherDisciplineClassroom.arel_table[:discipline_id]
              .eq(Discipline.arel_table[:id])
            .and(TeachingPlan.arel_table[:year]
              .eq(TeacherDisciplineClassroom.arel_table[:year]))
          )
          .join_sources
      )
      .joins(
        arel_table.join(Classroom.arel_table, Arel::Nodes::OuterJoin)
          .on(
            Classroom.arel_table[:grade_id]
              .eq(TeachingPlan.arel_table[:grade_id])
              .and(
                Classroom.arel_table[:id]
                  .eq(TeacherDisciplineClassroom.arel_table[:classroom_id])
              )
          )
          .join_sources
      )
      .where(TeacherDisciplineClassroom.arel_table[:teacher_id]
              .eq(teacher)
            .and(TeacherDisciplineClassroom.arel_table[:active]
              .eq('t')))
      .distinct
  end

  def self.by_knowledge_area(knowledge_area)
    joins(:knowledge_area_teaching_plan_knowledge_areas)
      .where(
        knowledge_area_teaching_plan_knowledge_areas: {
          knowledge_area_id: knowledge_area
        }
      )
  end
end
