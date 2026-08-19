# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarEventBatchManager::EventCreatorWorker, type: :worker do
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
      batch_status: BatchStatus::STARTED
    )
  end

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  before do
    allow(SystemNotificationCreator).to receive(:create!)
    allow(SchoolCalendarEventDays).to receive(:update_school_days)
  end

  it 'cria o evento e marca o lote como finalizado' do
    described_class.new.perform(entity.id, batch.id, user.id, 'create')

    expect(batch.reload.batch_status).to eq(BatchStatus::COMPLETED)
    expect(SchoolCalendarEvent.find_by(batch_id: batch.id, school_calendar_id: school_calendar.id)).to be_present
  end

  it 'atualiza os dias letivos uma única vez após criar os eventos' do
    described_class.new.perform(entity.id, batch.id, user.id, 'create')

    expect(SchoolCalendarEventDays).to have_received(:update_school_days).once
  end
end
