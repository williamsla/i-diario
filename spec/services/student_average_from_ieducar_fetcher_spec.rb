require 'rails_helper'

RSpec.describe StudentAverageFromIeducarFetcher, type: :service do
  let(:configuration) { double(:configuration, present?: true, to_api: {}) }
  let(:fetcher) { described_class.new(configuration) }
  let(:api) { instance_double(IeducarApi::StudentAverages) }
  let(:enrollment) { double(:enrollment, api_code: '99') }

  before do
    allow(Student).to receive(:find).with(1).and_return(double(:student, api_code: '10'))
    allow(Classroom).to receive(:find).with(2).and_return(double(:classroom, api_code: '20'))
    allow(Discipline).to receive(:find).with(3).and_return(double(:discipline, api_code: '30'))
    allow(StudentClassroomEnrollments).to receive(:for_student).with(1, 2).and_return([enrollment])
    allow(IeducarApi::StudentAverages).to receive(:new).and_return(api)
    allow(fetcher).to receive(:logger).and_return(Logger.new('/dev/null'))
  end

  it 'uses the score when the single object belongs to the requested stage' do
    allow(api).to receive(:fetch).and_return('data' => { 'stage' => 1, 'score' => '9.5' })

    expect(fetcher.fetch(1, 2, 3, 1)).to eq(9.5)
  end

  it 'returns nil when the single object belongs to another stage' do
    allow(api).to receive(:fetch).with(
      registration_id: '99',
      discipline_id: '30',
      stage: 1
    ).and_return('data' => { 'stage' => 2, 'score' => '10.0' })

    expect(fetcher.fetch(1, 2, 3, 1)).to be_nil
  end

  it 'matches a textual stage to the numeric step' do
    allow(api).to receive(:fetch).and_return('data' => { 'stage' => '2', 'score' => '8.0' })

    expect(fetcher.fetch(1, 2, 3, 2)).to eq(8.0)
  end

  it 'returns nil when the single object has no stage' do
    allow(api).to receive(:fetch).and_return('data' => { 'score' => '7.0' })

    expect(fetcher.fetch(1, 2, 3, 1)).to be_nil
  end

  it 'selects the requested stage from a list' do
    allow(api).to receive(:fetch).and_return(
      'data' => [
        { 'stage' => 1, 'score' => '9.5' },
        { 'stage' => '2', 'score' => '10.0' }
      ]
    )

    expect(fetcher.fetch(1, 2, 3, 2)).to eq(10.0)
  end

  it 'returns nil when the list has no record for the requested stage' do
    allow(api).to receive(:fetch).and_return(
      'data' => [{ 'stage' => 3, 'score' => '6.0' }]
    )

    expect(fetcher.fetch(1, 2, 3, 1)).to be_nil
  end
end
