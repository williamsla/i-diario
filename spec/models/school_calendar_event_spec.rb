# encoding: utf-8

require 'rails_helper'

RSpec.describe SchoolCalendarEvent, type: :model do
  subject { SchoolCalendarEvent.new(event_type: event_type) }

  let(:event_type) { nil }

  describe 'associations' do
    it { expect(subject).to belong_to(:school_calendar) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:start_date) }
    it { expect(subject).to validate_presence_of(:end_date) }
    it { expect(subject).to validate_presence_of(:description) }
    it { expect(subject).to validate_presence_of(:event_type) }
    
    context 'when :event_type is :extra_school' do
      let(:event_type) { EventTypes::EXTRA_SCHOOL }

      it { expect(subject).not_to validate_presence_of(:legend) }
    end

    context 'when :event_type is :no_school_with_frequency' do
      let(:event_type) { EventTypes::NO_SCHOOL_WITH_FREQUENCY }

      it { expect(subject).not_to validate_presence_of(:legend) }
    end

    context 'when :event_type is :no_school' do
      let(:event_type) { EventTypes::NO_SCHOOL }

      it { expect(subject).to validate_presence_of(:legend) }
    end

    context 'when :event_type is :extra_school_without_frequency' do
      let(:event_type) { EventTypes::EXTRA_SCHOOL_WITHOUT_FREQUENCY }

      it { expect(subject).to validate_presence_of(:legend) }
    end

    context 'when event is a saturday school day' do
      let(:school_calendar) { create(:school_calendar, :with_one_step) }
      let(:saturday) { Date.parse('2025-06-14') }

      it 'exige dia da semana de referência e data única' do
        event = build(
          :school_calendar_event,
          school_calendar: school_calendar,
          coverage: EventCoverageType::BY_UNITY,
          start_date: saturday,
          end_date: saturday,
          event_type: EventTypes::EXTRA_SCHOOL,
          equivalent_weekday: nil,
          periods: Periods.list
        )

        expect(event).not_to be_valid
        expect(event.errors[:equivalent_weekday]).to be_present
      end

      it 'é válido com dia da semana de referência informado' do
        event = build(
          :school_calendar_event,
          school_calendar: school_calendar,
          coverage: EventCoverageType::BY_UNITY,
          start_date: saturday,
          end_date: saturday,
          event_type: EventTypes::EXTRA_SCHOOL,
          equivalent_weekday: Workdays::FRIDAY,
          periods: Periods.list
        )

        expect(event).to be_valid
      end
    end
  end
end