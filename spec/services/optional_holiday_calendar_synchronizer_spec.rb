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
end
