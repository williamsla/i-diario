# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarEventBatchesController, type: :controller do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) { create(:user, :with_user_role_administrator) }
  let(:event_date) { Date.new(Date.current.year, 3, 9) }
  let!(:batch) do
    create(
      :school_calendar_event_batch,
      year: Date.current.year,
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
    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    request.env['REQUEST_PATH'] = ''
  end

  describe 'DELETE #destroy' do
    it 'apaga na hora o lote cujo evento já saiu do calendário' do
      batch_id = batch.id

      expect(SchoolCalendarEventBatchManager::EventDestroyerWorker).not_to receive(:perform_async)
      expect(SchoolCalendarEventBatchManager::EventDestroyerWorker).not_to receive(:new)

      delete :destroy, params: { locale: 'pt-BR', id: batch_id, keep_teacher_records: false }

      expect(SchoolCalendarEventBatch.find_by(id: batch_id)).to be_nil
      expect(response).to redirect_to(school_calendar_event_batches_path)
    end

    context 'quando solicita manter os registros dos professores' do
      it 'exclui o lote na hora e não deixa em andamento' do
        batch_id = batch.id

        delete :destroy, params: { locale: 'pt-BR', id: batch_id, keep_teacher_records: true }

        expect(SchoolCalendarEventBatch.find_by(id: batch_id)).to be_nil
        expect(response).to redirect_to(school_calendar_event_batches_path)
      end

      it 'não depende do Sidekiq para concluir a exclusão' do
        expect(SchoolCalendarEventBatchManager::EventDestroyerWorker).not_to receive(:perform_async)
        expect(SchoolCalendarEventBatchManager::EventDestroyerWorker).not_to receive(:new)

        delete :destroy, params: { locale: 'pt-BR', id: batch.id, keep_teacher_records: true }

        expect(SchoolCalendarEventBatch.find_by(id: batch.id)).to be_nil
      end
    end

    it 'exclui os eventos na requisição, sem deixar o lote em andamento no Sidekiq' do
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
      worker = instance_double(SchoolCalendarEventBatchManager::EventDestroyerWorker, perform: true)
      allow(SchoolCalendarEventBatchManager::EventDestroyerWorker).to receive(:new).and_return(worker)
      expect(SchoolCalendarEventBatchManager::EventDestroyerWorker).not_to receive(:perform_async)

      delete :destroy, params: { locale: 'pt-BR', id: batch.id, keep_teacher_records: false }

      expect(worker).to have_received(:perform).with(entity.id, batch.id, user.id, 'destroy', false)
    end
  end

  describe 'GET #index' do
    it 'conclui o cadastro preso que ainda não tinha evento no calendário' do
      batch.update_columns(created_at: 2.hours.ago, updated_at: 2.hours.ago)
      worker = instance_double(SchoolCalendarEventBatchManager::EventCreatorWorker, perform: true)
      allow(SchoolCalendarEventBatchManager::EventCreatorWorker).to receive(:new).and_return(worker)

      get :index, params: { locale: 'pt-BR' }

      expect(worker).to have_received(:perform).with(entity.id, batch.id, user.id, 'create')
    end
  end
end
