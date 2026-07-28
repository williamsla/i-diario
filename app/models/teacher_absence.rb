# frozen_string_literal: true

class TeacherAbsence < ApplicationRecord
  include Audit

  audited

  belongs_to :unity
  belongs_to :classroom, optional: true
  belongs_to :school_calendar
  belongs_to :teacher
  belongs_to :user
  belongs_to :discipline, optional: true

  has_many :teacher_absence_attachments, dependent: :destroy

  accepts_nested_attributes_for :teacher_absence_attachments, allow_destroy: true

  has_enumeration_for :coverage, with: TeacherAbsenceCoverage, skip_validation: true, create_helpers: true
  has_enumeration_for :period, with: Periods, skip_validation: true

  validates_date :absence_date
  validates_date :make_up_date, allow_blank: true
  validates :unity, :school_calendar, :teacher, :user, :reason, presence: true
  validates :absence_date, presence: true
  validates :classroom, presence: true, if: :coverage_by_classroom?
  validate :make_up_date_after_absence_date
  validate :periods_presence, if: :requires_periods?

  scope :ordered, -> { order(absence_date: :desc) }
  scope :by_unity, ->(unity_id) { where(unity_id: unity_id) }
  scope :by_classroom, ->(classroom_id) { where(classroom_id: classroom_id) }
  scope :by_teacher, ->(teacher_id) { where(teacher_id: teacher_id) }
  scope :by_discipline, ->(discipline_id) { where(discipline_id: discipline_id) }
  scope :by_absence_date_between, ->(start_at, end_at) {
    where(absence_date: start_at.to_date..end_at.to_date)
  }
  scope :with_make_up, -> { where(will_make_up: true).where.not(make_up_date: nil) }
  scope :by_make_up_date_between, ->(start_at, end_at) {
    with_make_up.where(make_up_date: start_at.to_date..end_at.to_date)
  }
  scope :for_classroom_or_unity, ->(classroom_id, unity_id) {
    where('(classroom_id = ? OR (classroom_id IS NULL AND unity_id = ?))', classroom_id, unity_id)
  }
  scope :by_period_in_periods, ->(period) {
    where("(periods IS NULL OR array_length(periods, 1) IS NULL OR ? = ANY(periods))", period.to_s)
  }

  # Normaliza periods: aceita string "1,2" ou array ["1","2"]
  def periods=(value)
    arr = case value
          when String then value.split(',').map(&:strip).reject(&:blank?)
          when Array then value.map(&:to_s).reject(&:blank?)
          else value
          end
    write_attribute(:periods, arr.presence&.sort || [])
  end

  # Períodos efetivos: usa periods; se vazio e existir period (legado), usa [period]
  def effective_periods
    if self[:periods].present?
      self[:periods]
    elsif period.present?
      [period.to_s]
    else
      []
    end
  end

  def coverage_by_classroom?
    coverage == TeacherAbsenceCoverage::BY_CLASSROOM
  end

  def coverage_whole_day?
    coverage == TeacherAbsenceCoverage::WHOLE_DAY
  end

  def coverage_all_classrooms?
    coverage == TeacherAbsenceCoverage::ALL_CLASSROOMS
  end

  # Apenas "Todas as turmas em um turno" exige seleção de turno; "Todo o dia" aplica a todos
  def requires_periods?
    coverage_all_classrooms?
  end

  def pending_make_up?
    will_make_up? && make_up_date.blank?
  end

  # Condição de disciplina: falta sem disciplina (nil) aplica a todas as disciplinas da turma
  def self.scope_by_discipline(rel, discipline_id)
    if discipline_id.present?
      rel.where('(teacher_absences.discipline_id IS NULL OR teacher_absences.discipline_id = ?)', discipline_id)
    else
      rel.where(discipline_id: nil)
    end
  end

  # Datas em que o professor faltou (aula não realizada) para turma/disciplina
  def self.absence_dates_for(classroom_id:, discipline_id:, teacher_id:, start_date:, end_date:, class_number: nil, unity_id: nil, period: nil)
    rel = by_teacher(teacher_id).by_absence_date_between(start_date, end_date)
    rel = rel.for_classroom_or_unity(classroom_id, unity_id || Classroom.find_by(id: classroom_id)&.unity_id)
    rel = rel.by_period_in_periods(period) if period.present?
    rel = scope_by_discipline(rel, discipline_id)
    rel = rel.where(class_number: class_number) if class_number.present?
    rel.pluck(:absence_date).map(&:to_date).to_set
  end

  # Verifica se existe falta do professor que bloqueia lançamento de frequência na data/turma/disciplina
  def self.blocks_frequency?(classroom_id:, teacher_id:, absence_date:, discipline_id: nil, class_numbers: nil, unity_id: nil, period: nil)
    date = absence_date.respond_to?(:to_date) ? absence_date.to_date : absence_date
    rel = by_teacher(teacher_id).where(absence_date: date)
    rel = rel.for_classroom_or_unity(classroom_id, unity_id || Classroom.find_by(id: classroom_id)&.unity_id)
    rel = rel.by_period_in_periods(period) if period.present?
    rel = scope_by_discipline(rel, discipline_id)
    if class_numbers.present?
      rel = rel.where(class_number: [nil] + Array(class_numbers).map(&:to_i))
    end
    rel.exists?
  end

  # Datas de reposição pendentes (aula a repor) para turma/disciplina
  def self.make_up_dates_for(classroom_id:, discipline_id:, teacher_id:, start_date:, end_date:, class_number: nil, unity_id: nil, period: nil)
    rel = by_teacher(teacher_id).by_make_up_date_between(start_date, end_date)
    rel = rel.for_classroom_or_unity(classroom_id, unity_id || Classroom.find_by(id: classroom_id)&.unity_id)
    rel = rel.by_period_in_periods(period) if period.present?
    rel = scope_by_discipline(rel, discipline_id)
    rel = rel.where(class_number: class_number) if class_number.present?
    rel.pluck(:make_up_date).map(&:to_date).to_set
  end

  def self.make_up_lessons_count_for(classroom_id:, discipline_id:, teacher_id:, date:, unity_id: nil, count_lessons_on_date: nil)
    rel = by_teacher(teacher_id).with_make_up.where(make_up_date: date)
    rel = rel.for_classroom_or_unity(classroom_id, unity_id || Classroom.find_by(id: classroom_id)&.unity_id)
    rel = scope_by_discipline(rel, discipline_id)

    rel.to_a.sum do |absence|
      if absence.class_number.present?
        1
      elsif count_lessons_on_date
        count = count_lessons_on_date.call(absence.absence_date).to_i
        count.positive? ? count : 1
      else
        1
      end
    end
  end

  private

  def periods_presence
    return if effective_periods.present?

    errors.add(:periods, :blank)
  end

  def make_up_date_after_absence_date
    return if make_up_date.blank? || absence_date.blank?

    if make_up_date < absence_date
      errors.add(:make_up_date, :must_be_after_absence_date)
    end
  end
end
