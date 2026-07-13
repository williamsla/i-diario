class GeneralConfiguration < ActiveRecord::Base
  acts_as_copy_target

  audited

  include Audit

  has_enumeration_for :backup_status, with: ApiSynchronizationStatus, create_helpers: true
  has_enumeration_for :security_level, with: SecurityLevels
  has_enumeration_for :allows_after_sales_relationship, with: AfterSaleRelationshipOptions
  has_enumeration_for :require_daily_activities_record,
                      with: RequireDailyActivitiesRecordTypes,
                      create_helpers: { prefix: true }

  mount_uploader :backup_file, BackupFileUploader

  validates :security_level, presence: true
  validates :allows_after_sales_relationship, presence: true
  validates :require_daily_activities_record, presence: true

  with_options presence: true, if: :notify_consecutive_or_alternate_absences do
    validates :max_consecutive_absence_days, numericality: { greater_than_or_equal_to: 2 }
    validates :max_alternate_absence_days, numericality: { greater_than_or_equal_to: 2 }
    validates :days_to_consider_alternate_absences, numericality: { greater_than_or_equal_to: 5 }
  end

  validate :valid_type_of_teaching
  validate :daily_frequency_with_type_of_teaching

  belongs_to :employees_default_role, class_name: 'Role', foreign_key: 'employees_default_role_id'

  def self.current
    self.first.presence || new
  end

  def self.annual_conceptual_evaluation?
    current.annual_conceptual_evaluation
  end

  def self.show_objectives?
    flag_enabled?(:show_objectives)
  end

  def self.semestral_recovery?
    flag_enabled?(:semestral_recovery)
  end

  def self.conceptual_exam_batch_layout?
    flag_enabled?(:conceptual_exam_batch_layout)
  end

  # Preferência: general_configurations (por município). Fallback: secrets.yml se a coluna ainda não existir.
  def self.flag_enabled?(attribute)
    record = current
    if record.has_attribute?(attribute)
      return ActiveRecord::Type::Boolean.new.cast(record.public_send(attribute))
    end

    secret_flag?(attribute)
  end
  private_class_method :flag_enabled?

  def self.secret_flag?(attribute)
    secrets = Rails.application.secrets
    keys = [attribute]
    keys << :SEMESTRAL_RECOVERY if attribute.to_sym == :semestral_recovery

    keys.any? do |key|
      next false unless secrets.respond_to?(key)

      value = secrets.public_send(key)
      value == true || value.to_s.strip.casecmp('true').zero? || value.to_s == '1'
    end
  rescue NoMethodError
    false
  end
  private_class_method :secret_flag?

  def allows_after_sales_relationship?
    allows_after_sales_relationship == AfterSaleRelationshipOptions::ALLOWS
  end

  def mark_with_error!(message)
    update_columns(
      backup_status: ApiSynchronizationStatus::ERROR,
      error_message: message
    )
  end

  private

  def daily_frequency_with_type_of_teaching
    return unless type_of_teaching
    return if types_of_teaching_was.sort == types_of_teaching.sort

    removed_types = types_of_teaching_was - types_of_teaching
    return unless DailyFrequencyStudent.find_by(type_of_teaching: removed_types)

    errors.add(:types_of_teaching, I18n.t('enumerations.types_of_teaching.used'))
  end

  def valid_type_of_teaching
    return if type_of_teaching.present?

    if types_of_teaching.blank?
      errors.add(:types_of_teaching, I18n.t('enumerations.types_of_teaching.blank'))
    elsif types_of_teaching.none? { |type| TypesOfTeaching.list.include?(type) }
      errors.add(:types_of_teaching, I18n.t('enumerations.types_of_teaching.invalid'))
    end
  end
end
