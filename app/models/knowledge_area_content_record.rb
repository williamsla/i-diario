class KnowledgeAreaContentRecord < ActiveRecord::Base
  include Audit
  include TeacherRelationable
  include Translatable

  teacher_relation_columns only: :knowledge_areas

  audited
  acts_as_copy_target

  before_destroy :valid_for_destruction?

  belongs_to :content_record, dependent: :destroy
  accepts_nested_attributes_for :content_record
  has_and_belongs_to_many :knowledge_areas

  delegate :classroom_id, :classroom, to: :content_record

  scope :by_unity_id, lambda { |unity_id| joins(content_record: :classroom).where(Classroom.arel_table[:unity_id].eq(unity_id) ) }
  scope :by_teacher_id, lambda { |teacher_id| joins(:content_record).where(content_records: { teacher_id: teacher_id }) }
  scope :by_classroom_id, lambda { |classroom_id| joins(:content_record).where(content_records: { classroom_id: classroom_id }) }
  scope :by_knowledge_area_id, lambda { |knowledge_area_id| joins(:knowledge_areas)
                                                            .where(knowledge_areas: {id: knowledge_area_id } )}
  scope :by_classroom_description, lambda { |description| joins(content_record: :classroom).where('unaccent(classrooms.description) ILIKE unaccent(?)', "%#{description}%" ) }
  scope :by_knowledge_area_description, lambda { |description| joins(:knowledge_areas).where('unaccent(knowledge_areas.description) ILIKE unaccent(?)', "%#{description}%" ) }
  scope :by_date, lambda { |date| joins(:content_record).where(content_records: { record_date: date.to_date }) }
  scope :by_date_range, lambda { |start_at, end_at| joins(:content_record).where("record_date <= ? AND record_date >= ?", end_at, start_at) }

  scope :ordered, -> { joins(:content_record).order(ContentRecord.arel_table[:record_date].desc) }
  scope :order_by_content_record_date, -> { joins(:content_record).order(ContentRecord.arel_table[:record_date]) }
  scope :by_author, lambda { |author_type, current_teacher_id|
    if author_type.to_s == PlansAuthors::MY_PLANS.to_s
      joins(:content_record).merge(ContentRecord.where(teacher_id: current_teacher_id))
    elsif author_type.to_s == PlansAuthors::ALL.to_s
      joins(:content_record)
    else
      joins(:content_record).merge(ContentRecord.where.not(teacher_id: current_teacher_id))
    end
  }
  scope :order_by_classroom, lambda {
    joins(content_record: :classroom).order(Classroom.arel_table[:description].desc)
  }

  validates :content_record, presence: true
  validates :knowledge_area_ids, presence: true

  validate :uniqueness_of_knowledge_area_content_record
  validate :ensure_is_school_day

  delegate :contents, :objectives, :classroom, :record_date, to: :content_record
  delegate :grades, to: :classroom

  def knowledge_area_ids
    knowledge_areas.collect(&:id).join(',')
  end

  private

  def valid_for_destruction?
    @valid_for_destruction if defined?(@valid_for_destruction)
    @valid_for_destruction = begin
      content_record.validation_type = :destroy
      content_record.valid?
      forbidden_error = I18n.t('errors.messages.not_allowed_to_post_in_date')
      if content_record.errors[:record_date].include?(forbidden_error)
        errors.add(:base, forbidden_error)
        false
      else
        true
      end
    end
  end

  def uniqueness_of_knowledge_area_content_record
    return unless content_record.present? && content_record.classroom.present? && content_record.record_date.present?
    return unless knowledge_areas.present?

    # Obtém os IDs das áreas de conhecimento como array ordenado
    current_knowledge_area_ids = knowledge_areas.map(&:id).sort
    return if current_knowledge_area_ids.empty?

    # Busca registros existentes com mesma turma, professor e data
    base_query = KnowledgeAreaContentRecord.by_teacher_id(content_record.teacher_id)
      .by_classroom_id(content_record.classroom_id)
      .by_date(content_record.record_date)

    base_query = base_query.where.not(id: id) if persisted?

    # Busca registros que contêm todas as áreas de conhecimento especificadas
    # Usa uma subquery mais segura para evitar problemas com GROUP BY
    matching_records = base_query
      .joins(:knowledge_areas)
      .where(knowledge_areas: { id: current_knowledge_area_ids })
      .group('knowledge_area_content_records.id')
      .having('COUNT(DISTINCT knowledge_areas.id) = ?', current_knowledge_area_ids.size)
      .select('knowledge_area_content_records.id')

    # Se encontrou registros com o mesmo número de áreas, verifica se são exatamente as mesmas
    if matching_records.any?
      # Carrega os registros completos com suas áreas de conhecimento
      candidate_ids = matching_records.pluck(:id)
      candidates = KnowledgeAreaContentRecord.where(id: candidate_ids).includes(:knowledge_areas)
      
      candidates.each do |record|
        existing_knowledge_area_ids = record.knowledge_areas.map(&:id).sort
        
        if existing_knowledge_area_ids == current_knowledge_area_ids
          errors.add(:knowledge_area_ids, :knowledge_area_in_use)
          return
        end
      end
    end
  end

  def ensure_is_school_day
    return unless content_record.present? &&
                  content_record.school_calendar.present? &&
                  record_date.present?

    unless content_record.school_calendar.school_day?(record_date, grades.first, classroom_id)
      errors.add(:base, "")
      content_record.errors.add(:record_date, :not_school_calendar_day)
    end
  end

end
