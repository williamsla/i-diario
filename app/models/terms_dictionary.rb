class TermsDictionary < ApplicationRecord
  acts_as_copy_target
  audited

  include Audit

  EDUCAMAIS_LABEL_MAX_LENGTH = 50

  before_validation :normalize_educamais_label

  validates :presence_identifier_character, presence: true, length: { is: 1 }
  validates :educamais_label, length: { maximum: EDUCAMAIS_LABEL_MAX_LENGTH }, allow_blank: true

  def self.current
    self.first || new
  end

  def self.cached_current
    Rails.cache.fetch("#{Entity.current.id}_current_terms_dictionary", expires_in: 10.minutes) do
      self.current
    end
  end

  def self.educamais_display_name
    custom = cached_current.try(:educamais_label).to_s.strip.presence if Entity.current.present?
    custom || I18n.t('navigation.educamais')
  end

  private

  def normalize_educamais_label
    self.educamais_label = educamais_label.to_s.strip.presence
  end
end
