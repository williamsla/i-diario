# frozen_string_literal: true

class SchoolSaturdaysMapping
  WEEKDAY_NUMBERS = {
    'sunday' => 0,
    'monday' => 1,
    'tuesday' => 2,
    'wednesday' => 3,
    'thursday' => 4,
    'friday' => 5,
    'saturday' => 6
  }.freeze

  def self.weekday_name_for(date, school_calendar: nil)
    new(school_calendar: school_calendar).weekday_name_for(date)
  end

  def self.weekday_number_for(date, school_calendar: nil)
    new(school_calendar: school_calendar).weekday_number_for(date)
  end

  def self.mapping_for(school_calendar: nil)
    new(school_calendar: school_calendar).mapping
  end

  def self.saturday_school_day_without_equivalent_weekday?(date, classroom:, school_calendar: nil)
    new(school_calendar: school_calendar).saturday_school_day_without_equivalent_weekday?(date, classroom: classroom)
  end

  def initialize(school_calendar: nil)
    @school_calendar = school_calendar
  end

  def weekday_name_for(date)
    date = date.to_date
    return date.strftime('%A').downcase unless date.saturday?

    equivalent_weekday(date) || date.strftime('%A').downcase
  end

  def weekday_number_for(date)
    date = date.to_date
    WEEKDAY_NUMBERS.fetch(weekday_name_for(date), date.wday)
  end

  def mapping
    @mapping ||= load_yaml_mapping.merge(load_database_mapping)
  end

  def equivalent_weekday(date)
    mapping[date.to_date.strftime('%Y-%m-%d')]
  end

  def saturday_school_day_without_equivalent_weekday?(date, classroom:)
    date = date.to_date
    return false unless date.saturday?
    return false if equivalent_weekday(date).present?

    saturday_school_day?(date, classroom: classroom)
  end

  def saturday_school_day?(date, classroom:)
    date = date.to_date
    return false unless date.saturday?

    school_calendar = school_calendar_for(classroom, date)
    return false unless school_calendar

    if classroom.present?
      grade_id = classroom.classrooms_grades.pluck(:grade_id).first
      SchoolDayChecker.new(school_calendar, date, grade_id, classroom.id, nil).school_day?
    else
      school_calendar.events.by_date(date).school_event.exists?
    end
  end

  private

  def school_calendar_for(classroom, date)
    return @school_calendar if @school_calendar

    classroom = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
    return nil unless classroom

    CurrentSchoolCalendarFetcher.new(classroom.unity, classroom, date.year).fetch
  rescue StandardError
    SchoolCalendar.find_by(unity_id: classroom.unity_id, year: date.year)
  end

  def load_yaml_mapping
    config_path = Rails.root.join('config', 'sabados_letivos.yml')
    return {} unless File.exist?(config_path)

    YAML.load_file(config_path) || {}
  end

  def load_database_mapping
    scope = SchoolCalendarEvent
            .joins(:school_calendar)
            .where.not(equivalent_weekday: [nil, ''])
            .where(event_type: [
                     EventTypes::EXTRA_SCHOOL,
                     EventTypes::EXTRA_SCHOOL_WITHOUT_FREQUENCY
                   ])

    scope = scope.where(school_calendar_id: @school_calendar.id) if @school_calendar

    result = {}
    scope.find_each do |event|
      (event.start_date..event.end_date).each do |day|
        next unless day.saturday?

        result[day.strftime('%Y-%m-%d')] = event.equivalent_weekday
      end
    end
    result
  end
end
