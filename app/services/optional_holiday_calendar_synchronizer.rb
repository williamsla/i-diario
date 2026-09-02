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
    if @optional_holiday.makeup_scope_municipal?
      return if @optional_holiday.make_up_date.blank?

      calendars.find_each do |school_calendar|
        upsert_event(
          school_calendar: school_calendar,
          event_type: MAKEUP_EVENT_TYPE,
          date: @optional_holiday.make_up_date,
          description: makeup_description,
          legend: nil,
          equivalent_weekday: @optional_holiday.equivalent_weekday,
          show_in_frequency_record: true
        )
      end
    else
      @optional_holiday.optional_holiday_unity_makeups.each do |unity_makeup|
        school_calendar = calendars.detect { |calendar| calendar.unity_id == unity_makeup.unity_id } ||
                          SchoolCalendar.find_by(year: @optional_holiday.year, unity_id: unity_makeup.unity_id)
        next if school_calendar.blank?

        upsert_event(
          school_calendar: school_calendar,
          event_type: MAKEUP_EVENT_TYPE,
          date: unity_makeup.make_up_date,
          description: makeup_description,
          legend: nil,
          equivalent_weekday: unity_makeup.equivalent_weekday,
          show_in_frequency_record: true
        )
      end
    end
  end

  def destroy_stale_events(calendars)
    expected_ids = expected_event_keys(calendars)
    @optional_holiday.school_calendar_events.find_each do |event|
      key = [event.school_calendar_id, event.event_type]
      next if expected_ids.include?(key)

      event.keep_teacher_records = true
      event.destroy
    end
  end

  def expected_event_keys(calendars)
    keys = calendars.map { |calendar| [calendar.id, HOLIDAY_EVENT_TYPE] }

    if @optional_holiday.makeup_scope_municipal?
      if @optional_holiday.make_up_date.present?
        calendars.each { |calendar| keys << [calendar.id, MAKEUP_EVENT_TYPE] }
      end
    else
      @optional_holiday.optional_holiday_unity_makeups.each do |unity_makeup|
        school_calendar = calendars.detect { |calendar| calendar.unity_id == unity_makeup.unity_id }
        keys << [school_calendar.id, MAKEUP_EVENT_TYPE] if school_calendar
      end
    end

    keys
  end

  def upsert_event(school_calendar:, event_type:, date:, description:, legend:, equivalent_weekday:, show_in_frequency_record:)
    event = SchoolCalendarEvent.find_or_initialize_by(
      school_calendar_id: school_calendar.id,
      optional_holiday_id: @optional_holiday.id,
      event_type: event_type
    )

    event.assign_attributes(
      description: description,
      start_date: date,
      end_date: date,
      periods: @optional_holiday.effective_periods,
      legend: legend,
      equivalent_weekday: equivalent_weekday,
      show_in_frequency_record: show_in_frequency_record,
      coverage: EventCoverageType::BY_UNITY
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
