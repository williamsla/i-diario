# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarEventBatch, type: :model do
  describe 'saturday school day mapping' do
    let(:saturday) { Date.parse('2025-06-14') }

    it 'permite sábado letivo sem dia da semana de referência' do
      batch = build(
        :school_calendar_event_batch,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: nil,
        periods: Periods.list
      )

      expect(batch).to be_valid
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

  describe '#mark_as_completed!' do
    it 'atualiza a situação para finalizado mesmo quando o registro é inválido' do
      batch = build(
        :school_calendar_event_batch,
        start_date: Date.parse('2025-06-14'),
        end_date: Date.parse('2025-06-16'),
        event_type: EventTypes::EXTRA_SCHOOL,
        batch_status: BatchStatus::STARTED
      )
      batch.save(validate: false)

      batch.mark_as_completed!

      expect(batch.reload.batch_status).to eq(BatchStatus::COMPLETED)
      expect(batch.error_message).to be_nil
    end
  end

  describe '#mark_with_error!' do
    it 'atualiza a situação para erro e trunca a mensagem' do
      batch = create(
        :school_calendar_event_batch,
        start_date: Date.parse('2025-06-14'),
        end_date: Date.parse('2025-06-14'),
        batch_status: BatchStatus::STARTED
      )

      batch.mark_with_error!('x' * 300)

      expect(batch.reload.batch_status).to eq(BatchStatus::ERROR)
      expect(batch.error_message.length).to be <= 255
    end
  end
end
