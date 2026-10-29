require 'rails_helper'

RSpec.describe Api::V2::SynchronizationsController, type: :controller do
  let(:configuration) { create(:ieducar_api_configuration, api_security_token: 'security-token') }
  let(:author) { create(:user) }

  around(:each) do |example|
    Entity.find_by_domain('test.host').using_connection do
      example.run
    end
  end

  before do
    configuration
    author
    allow(IeducarSynchronizerWorker).to receive(:perform_in).and_return('job-123')
    allow_any_instance_of(WorkerBatch).to receive(:start!)
  end

  describe 'POST #create' do
    it 'starts a simple synchronization with the access key' do
      request.headers['token'] = configuration.token

      post :create, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq(ApiSynchronizationStatus::STARTED)
      expect(body['full_synchronization']).to eq(false)
      expect(IeducarSynchronizerWorker).to have_received(:perform_in).with(
        1.second,
        Entity.find_by_domain('test.host').id,
        be_a(Integer),
        false,
        true
      )
    end

    it 'accepts the diary security token' do
      request.headers['token'] = configuration.api_security_token

      post :create, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
    end

    it 'rejects the secret key and an unknown token' do
      request.headers['token'] = configuration.secret_token

      post :create, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:unauthorized)

      request.headers['token'] = 'token-diferente'

      post :create, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the synchronization already running' do
      request.headers['token'] = configuration.token
      running = create(:ieducar_api_synchronization, ieducar_api_configuration: configuration, status: ApiSynchronizationStatus::STARTED, author: author)

      post :create, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(running.id)
      expect(IeducarSynchronizerWorker).not_to have_received(:perform_in)
    end
  end

  describe 'GET #current' do
    it 'returns the started synchronization' do
      request.headers['token'] = configuration.token
      running = create(:ieducar_api_synchronization, ieducar_api_configuration: configuration, status: ApiSynchronizationStatus::STARTED, author: author)

      get :current, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(running.id)
    end

    it 'returns the last finished synchronization when none is running' do
      request.headers['token'] = configuration.token
      finished = create(:ieducar_api_synchronization, ieducar_api_configuration: configuration, status: ApiSynchronizationStatus::COMPLETED, author: author)

      get :current, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq(ApiSynchronizationStatus::COMPLETED)
      expect(JSON.parse(response.body)['id']).to eq(finished.id)
    end
  end
end
