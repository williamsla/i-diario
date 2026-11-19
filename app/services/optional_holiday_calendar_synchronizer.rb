# frozen_string_literal: true

class OptionalHolidayCalendarSynchronizer
  HOLIDAY_EVENT_TYPE = EventTypes::NO_SCHOOL
  MAKEUP_EVENT_TYPE = EventTypes::EXTRA_SCHOOL

  def initialize(optional_holiday)
    @optional_holiday = optional_holiday
  end

  def sync
    calendars = SchoolCalendar.by_year(@optional_holiday.year)
    holiday_events = []

    calendars.find_each do |school_calendar|
      holiday_events << upsert_event(
        school_calendar: school_calendar,
        event_type: HOLIDAY_EVENT_TYPE,
        date: @optional_holiday.holiday_date,
        description: @optional_holiday.description,
        legend: OptionalHoliday::HOLIDAY_LEGEND,
        equivalent_weekday: nil,
        show_in_frequency_record: true
      )
    end

    sync_makeup_events(calendars)
    destroy_stale_events(calendars)

    created_holiday_events = holiday_events.compact
    if created_holiday_events.any?
      SchoolCalendarEventDays.update_school_days(
        calendars,
        created_holiday_events,
        'create',
        @optional_holiday.holiday_date,
        @optional_holiday.holiday_date
      )
    end
  end

  def destroy_events
    events = @optional_holiday.school_calendar_events.to_a
    calendars = SchoolCalendar.where(id: events.map(&:school_calendar_id).uniq)

    if events.any?
      SchoolCalendarEventDays.update_school_days(
        calendars,
        events.select { |event| event.event_type == HOLIDAY_EVENT_TYPE },
        'destroy',
        @optional_holiday.holiday_date,
        @optional_holiday.holiday_date
      )
    end

    events.each do |event|
      event.keep_teacher_records = true
      event.destroy
    end
  end

  private

  def sync_makeup_events(calendars)
    calendars.each do |school_calendar|
      makeup_slots_for(school_calendar).each do |slot|
        upsert_event(
          school_calendar: school_calendar,
          event_type: MAKEUP_EVENT_TYPE,
          date: slot[:date],
          description: makeup_description,
          legend: nil,
          equivalent_weekday: slot[:equivalent_weekday],
          show_in_frequency_record: true,
          course_id: slot[:course_id],
          coverage: slot[:coverage]
        )
      end
    end
  end

  def destroy_stale_events(calendars)
    expected_ids = expected_event_keys(calendars)
    @optional_holiday.school_calendar_events.find_each do |event|
      key = [event.school_calendar_id, event.event_type, event.course_id]
      next if expected_ids.include?(key)

      event.keep_teacher_records = true
      event.destroy
    end
  end

  def expected_event_keys(calendars)
    keys = calendars.map { |calendar| [calendar.id, HOLIDAY_EVENT_TYPE, nil] }

    calendars.each do |calendar|
      makeup_slots_for(calendar).each do |slot|
        keys << [calendar.id, MAKEUP_EVENT_TYPE, slot[:course_id]]
      end
    end

    keys
  end

  def makeup_slots_for(school_calendar)
    if @optional_holiday.makeup_scope_municipal?
      slots_from(
        general_date: @optional_holiday.make_up_date,
        general_weekday: @optional_holiday.equivalent_weekday,
        specifics: @optional_holiday.optional_holiday_course_makeups,
        unity_id: nil
      )
    else
      makeups = @optional_holiday.optional_holiday_unity_makeups.select do |makeup|
        makeup.unity_id == school_calendar.unity_id
      end
      general = makeups.detect { |makeup| makeup.course_id.nil? }
      slots_from(
        general_date: general&.make_up_date,
        general_weekday: general&.equivalent_weekday,
        specifics: makeups.select { |makeup| makeup.course_id.present? },
        unity_id: school_calendar.unity_id
      )
    end
  end

  def slots_from(general_date:, general_weekday:, specifics:, unity_id:)
    specifics = specifics.to_a.select { |makeup| makeup.make_up_date.present? && makeup.course_id.present? }
    if specifics.empty?
      return [] if general_date.blank?

      return [{
        date: general_date,
        course_id: nil,
        equivalent_weekday: general_weekday,
        coverage: EventCoverageType::BY_UNITY
      }]
    end

    slots = specifics.map do |makeup|
      {
        date: makeup.make_up_date,
        course_id: makeup.course_id,
        equivalent_weekday: makeup.equivalent_weekday,
        coverage: EventCoverageType::BY_COURSE
      }
    end

    covered_course_ids = specifics.map(&:course_id)
    if general_date.present?
      course_ids_for(unity_id).each do |course_id|
        next if covered_course_ids.include?(course_id)

        slots << {
          date: general_date,
          course_id: course_id,
          equivalent_weekday: general_weekday,
          coverage: EventCoverageType::BY_COURSE
        }
      end
    end

    slots
  end

  def course_ids_for(unity_id)
    @course_ids_for ||= {}
    @course_ids_for[unity_id] ||= OptionalHoliday.courses_for_year(@optional_holiday.year, unity_id: unity_id)
                                                 .unscope(:order)
                                                 .pluck(:id)
  end

  def upsert_event(school_calendar:, event_type:, date:, description:, legend:, equivalent_weekday:, show_in_frequency_record:, course_id: nil, coverage: EventCoverageType::BY_UNITY)
    event = SchoolCalendarEvent.find_or_initialize_by(
      school_calendar_id: school_calendar.id,
      optional_holiday_id: @optional_holiday.id,
      event_type: event_type,
      course_id: course_id
    )

    event.assign_attributes(
      description: description,
      start_date: date,
      end_date: date,
      periods: @optional_holiday.effective_periods,
      legend: legend,
      equivalent_weekday: equivalent_weekday,
      show_in_frequency_record: show_in_frequency_record,
      coverage: coverage,
      course_id: course_id
    )

    if event.save
      event
    else
      Rails.logger.warn(
        "[OptionalHolidayCalendarSynchronizer] Não foi possível salvar evento #{event_type} " \
        "para calendário #{school_calendar.id}: #{event.errors.full_messages.join(', ')}"
      )
      nil
    end
  end

  def makeup_description
    "#{@optional_holiday.description} (reposição)"
  end
end
