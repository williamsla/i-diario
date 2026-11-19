# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionalHolidayCalendarSynchronizer do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  around(:each) do |example|
    entity.using_connection { example.run }
  end

  let(:unity) { create(:unity) }
  let!(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity) }
  let(:user) { create(:user) }
  let(:holiday) do
    create(
      :optional_holiday,
      year: school_calendar.year,
      user: user,
      holiday_date: Date.new(school_calendar.year, 5, 15),
      make_up_date: Date.new(school_calendar.year, 5, 17),
      periods: %w[2],
      makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
    )
  end

  it 'creates a no-school event and a make-up extra-school event' do
    allow(SchoolCalendarEventDays).to receive(:update_school_days)

    described_class.new(holiday).sync

    events = SchoolCalendarEvent.where(optional_holiday_id: holiday.id, school_calendar_id: school_calendar.id)
    expect(events.map(&:event_type)).to include(EventTypes::NO_SCHOOL, EventTypes::EXTRA_SCHOOL)
    expect(events.find_by(event_type: EventTypes::NO_SCHOOL).start_date).to eq(holiday.holiday_date)
    expect(events.find_by(event_type: EventTypes::EXTRA_SCHOOL).start_date).to eq(holiday.make_up_date)
    expect(events.first.periods).to eq(%w[2])
  end

  it 'creates one extra school event per course when makeup dates differ' do
    allow(SchoolCalendarEventDays).to receive(:update_school_days)
    fundamental = create(:course, description: 'Fundamental')
    eja = create(:course, description: 'EJA')
    fundamental_classroom = create(:classroom, unity: unity, year: school_calendar.year)
    eja_classroom = create(:classroom, unity: unity, year: school_calendar.year)
    create(:classrooms_grade, classroom: fundamental_classroom, grade: create(:grade, course: fundamental))
    create(:classrooms_grade, classroom: eja_classroom, grade: create(:grade, course: eja))
    specific_date = holiday.make_up_date + 2.days
    create(
      :optional_holiday_course_makeup,
      optional_holiday: holiday,
      course: fundamental,
      make_up_date: specific_date
    )

    described_class.new(holiday).sync

    events = SchoolCalendarEvent.where(
      optional_holiday_id: holiday.id,
      school_calendar_id: school_calendar.id,
      event_type: EventTypes::EXTRA_SCHOOL
    )
    expect(events.find_by(course_id: fundamental.id).start_date).to eq(specific_date)
    expect(events.find_by(course_id: eja.id).start_date).to eq(holiday.make_up_date)
    expect(events.where(course_id: nil)).to be_empty
    expect(events.map(&:coverage).uniq).to eq([EventCoverageType::BY_COURSE])
  end
end
