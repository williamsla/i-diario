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

  describe '.resolve_stuck_batches!' do
    let(:event_date) { Date.new(Date.current.year, 3, 9) }

    def stick!(batch, created_at:, updated_at:)
      batch.update_columns(
        batch_status: BatchStatus::STARTED,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    it 'finaliza o cadastro que já gravou o evento no calendário' do
      batch = create(
        :school_calendar_event_batch,
        start_date: event_date,
        end_date: event_date,
        batch_status: BatchStatus::STARTED
      )
      create(
        :school_calendar_event,
        school_calendar: create(:school_calendar, :with_one_step),
        batch_id: batch.id,
        start_date: event_date,
        end_date: event_date,
        event_type: EventTypes::EXTRA_SCHOOL,
        coverage: EventCoverageType::BY_UNITY,
        periods: Periods.list
      )
      stick!(batch, created_at: 2.hours.ago, updated_at: 2.hours.ago)

      expect(described_class.resolve_stuck_batches!).to eq([])
      expect(batch.reload.batch_status).to eq(BatchStatus::COMPLETED)
    end

    it 'remove o lote cuja exclusão já tirou o evento do calendário' do
      batch = create(
        :school_calendar_event_batch,
        start_date: event_date,
        end_date: event_date,
        batch_status: BatchStatus::STARTED
      )
      stick!(batch, created_at: 2.hours.ago, updated_at: 1.hour.ago)

      expect(described_class.resolve_stuck_batches!).to eq([])
      expect(described_class.find_by(id: batch.id)).to be_nil
    end

    it 'devolve o cadastro que ainda não gravou evento para ser concluído' do
      batch = create(
        :school_calendar_event_batch,
        start_date: event_date,
        end_date: event_date,
        batch_status: BatchStatus::STARTED
      )
      stick!(batch, created_at: 2.hours.ago, updated_at: 2.hours.ago)

      expect(described_class.resolve_stuck_batches!).to eq([batch.id])
      expect(batch.reload.batch_status).to eq(BatchStatus::STARTED)
    end

    it 'não mexe em lote que acabou de entrar em andamento' do
      batch = create(
        :school_calendar_event_batch,
        start_date: event_date,
        end_date: event_date,
        batch_status: BatchStatus::STARTED
      )

      expect(described_class.resolve_stuck_batches!).to eq([])
      expect(batch.reload.batch_status).to eq(BatchStatus::STARTED)
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
