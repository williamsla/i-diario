# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarEventBatch, type: :model do
  describe 'saturday school day mapping' do
    let(:saturday) { Date.parse('2025-06-14') }

    it 'exige dia da semana de referência para sábado letivo' do
      batch = build(
        :school_calendar_event_batch,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: nil,
        periods: Periods.list
      )

      expect(batch).not_to be_valid
      expect(batch.errors[:equivalent_weekday]).to be_present
    end

    it 'é válido com dia da semana de referência informado' do
      batch = build(
        :school_calendar_event_batch,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: Workdays::MONDAY,
        periods: Periods.list
      )

      expect(batch).to be_valid
    end
  end
end
