class AvaliationMultipleCreatorClassroomForm
  include ActiveModel::Model
  include I18n::Alchemy
  localize :test_date, :using => :date


  attr_accessor :classroom_id, :test_date, :classes, :avaliation_multiple_creator_form

  validates :classroom_id,      presence: true
  validates :test_date,         presence: true, school_calendar_day: true
  validates :classes,           presence: true
  validate :is_school_term_day?

  def classroom
    @classroom ||= Classroom.find_by(id: classroom_id)
  end

  def school_calendar
    avaliation_multiple_creator_form.school_calendar
  end

  protected

  def is_school_term_day?
    return if test_setting.nil? ||
              [ExamSettingTypes::GENERAL,
               ExamSettingTypes::GENERAL_BY_SCHOOL].include?(test_setting.exam_setting_type)

    school_term_type_step = test_setting.school_term_type_step
    return if school_term_type_step.blank?

    return if school_calendar.school_term_day?(school_term_type_step, test_date, classroom)

    errors.add(:test_date, :must_be_school_term_day)
  end

  def test_setting
    avaliation_multiple_creator_form.test_setting
  end
end
