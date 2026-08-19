# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarEventBatchManager::EventDestroyerWorker, type: :worker do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) { create(:user, :with_user_role_administrator) }
  let(:event_date) { Date.new(Date.current.year, 3, 9) }
  let!(:school_calendar) { create(:school_calendar, :with_one_step) }
  let(:batch) do
    create(
      :school_calendar_event_batch,
      year: school_calendar.year,
      start_date: event_date,
      end_date: event_date,
      event_type: EventTypes::EXTRA_SCHOOL,
      periods: Periods.list,
      batch_status: BatchStatus::COMPLETED
    )
  end
  let!(:event) do
    create(
      :school_calendar_event,
      school_calendar: school_calendar,
      batch_id: batch.id,
      start_date: event_date,
      end_date: event_date,
      event_type: EventTypes::EXTRA_SCHOOL,
      coverage: EventCoverageType::BY_UNITY,
      periods: Periods.list
    )
  end

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  before do
    allow(SystemNotificationCreator).to receive(:create!)
    allow(SchoolCalendarEventDays).to receive(:update_school_days)
  end

  it 'exclui o evento e atualiza os dias letivos por padrão' do
    described_class.new.perform(entity.id, batch.id, user.id, 'destroy')

    expect(SchoolCalendarEventDays).to have_received(:update_school_days)
    expect(SchoolCalendarEventBatch.find_by(id: batch.id)).to be_nil
    expect(SchoolCalendarEvent.find_by(id: event.id)).to be_nil
  end

  it 'exclui o evento e mantém os registros dos professores quando solicitado' do
    described_class.new.perform(entity.id, batch.id, user.id, 'destroy', true)

    expect(SchoolCalendarEventDays).not_to have_received(:update_school_days)
    expect(SchoolCalendarEventBatch.find_by(id: batch.id)).to be_nil
    expect(SchoolCalendarEvent.find_by(id: event.id)).to be_nil
  end
end
