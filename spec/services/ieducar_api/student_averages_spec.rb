require 'spec_helper'

RSpec.describe IeducarApi::StudentAverages, type: :service do
  let(:url) { 'https://ieducar.test' }
  let(:access_key) { 'access-key' }
  let(:secret_key) { 'secret-key' }
  let(:unity_id) { 1 }
  let(:score_body) { '{"data":{"stage":2,"score":"7.5"}}' }

  subject do
    described_class.new(
      url: url,
      access_key: access_key,
      secret_key: secret_key,
      unity_id: unity_id
    )
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    described_class.reset_throttle!
    example.run
  ensure
    Rails.cache = original_cache
    described_class.reset_throttle!
  end

  let(:info_logs) { [] }
  let(:warn_logs) { [] }
  let(:error_logs) { [] }

  before do
    allow(subject).to receive(:sleep)
    allow(Rails.logger).to receive(:info) { |message| info_logs << message }
    allow(Rails.logger).to receive(:warn) { |message| warn_logs << message }
    allow(Rails.logger).to receive(:error) { |message| error_logs << message }
    allow(Sidekiq.logger).to receive(:info)
  end

  describe '#fetch' do
    it 'returns the parsed score' do
      expect(RestClient::Request).to receive(:execute).once.and_return(score_body)

      result = subject.fetch(registration_id: 19_664, discipline_id: 3, stage: 2)

      expect(result.dig('data', 'score')).to eq('7.5')
    end

    it 'sends the keys to the API and keeps them out of the log' do
      expect(RestClient::Request).to receive(:execute).with(
        hash_including(url: include("access_key=#{access_key}", "secret_key=#{secret_key}"))
      ).and_return(score_body)

      subject.fetch(registration_id: 1, discipline_id: 2, stage: 1)

      expect(info_logs.join).to include('registration_id=1')
      expect(info_logs.join).not_to include(access_key)
      expect(info_logs.join).not_to include(secret_key)
    end

    it 'reuses the cached response for the same registration, discipline and stage' do
      expect(RestClient::Request).to receive(:execute).once.and_return(score_body)

      2.times { subject.fetch(registration_id: 1, discipline_id: 2, stage: 1) }
    end

    it 'retries when the API returns 429 and then succeeds' do
      limited = RestClient::TooManyRequests.new(rate_limit_response(retry_after: '1'))

      expect(RestClient::Request).to receive(:execute).ordered.and_raise(limited)
      expect(RestClient::Request).to receive(:execute).ordered.and_return(score_body)

      result = subject.fetch(registration_id: 1, discipline_id: 2, stage: 2)

      expect(result.dig('data', 'score')).to eq('7.5')
      expect(warn_logs.join).to include('HTTP 429')
    end

    it 'raises a clear error after repeated 429 responses' do
      limited = RestClient::TooManyRequests.new(rate_limit_response)
      allow(RestClient::Request).to receive(:execute).and_raise(limited)

      expect {
        subject.fetch(registration_id: 1, discipline_id: 2, stage: 2)
      }.to raise_error(
        IeducarApi::Base::ApiError,
        'A API do i-Educar limitou o número de consultas de nota (HTTP 429). Aguarde alguns instantes e tente novamente.'
      )

      logged_error = error_logs.join
      expect(logged_error).to include('HTTP: 429')
      expect(logged_error).not_to include(access_key)
      expect(logged_error).not_to include(secret_key)
    end

    it 'requires registration, discipline and stage' do
      expect { subject.fetch(discipline_id: 2, stage: 1) }.to raise_error(IeducarApi::Base::ApiError, /registration_id/)
      expect { subject.fetch(registration_id: 1, stage: 1) }.to raise_error(IeducarApi::Base::ApiError, /discipline_id/)
      expect { subject.fetch(registration_id: 1, discipline_id: 2) }.to raise_error(IeducarApi::Base::ApiError, /stage/)
    end
  end

  def rate_limit_response(retry_after: nil)
    headers = {}
    headers[:retry_after] = retry_after if retry_after

    Struct.new(:code, :headers, :body).new(429, headers, '429 Too Many Requests')
  end
end
