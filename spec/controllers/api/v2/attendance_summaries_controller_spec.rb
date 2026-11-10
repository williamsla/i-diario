require 'rails_helper'

RSpec.describe Api::V2::AttendanceSummariesController, type: :controller do
  describe 'GET #show' do
    let(:unity) { create(:unity, api_code: '6') }
    let(:configuration) { create(:ieducar_api_configuration, api_security_token: 'security-token') }
    let(:data) { Date.new(2026, 11, 9) }
    let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, year: data.year) }
    let(:classroom) { create(:classroom, unity: unity, year: data.year, period: Periods::MATUTINAL) }
    let(:present_student) { create(:student) }
    let(:absent_student) { create(:student) }
    let(:mixed_student) { create(:student) }

    around(:each) do |example|
      Entity.find_by_domain('test.host').using_connection do
        example.run
      end
    end

    before do
      request.headers['token'] = configuration.token
    end

    def launch_frequency(classroom_record, period, student, present)
      frequency = create(
        :daily_frequency,
        unity: unity,
        classroom: classroom_record,
        school_calendar: school_calendar,
        frequency_date: data
      )
      frequency.update_columns(period: period)
      classroom_record.update_columns(period: classroom_record.period)

      create(
        :daily_frequency_student,
        daily_frequency: frequency,
        student: student,
        present: present,
        active: true
      )
    end

    it 'counts present and absent students of the selected shift from teacher frequencies' do
      launch_frequency(classroom, Periods::MATUTINAL, present_student, true)
      launch_frequency(classroom, Periods::MATUTINAL, absent_student, false)
      launch_frequency(classroom, Periods::MATUTINAL, mixed_student, false)
      launch_frequency(classroom, Periods::MATUTINAL, mixed_student, true)

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'matutino', locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['presentes']).to eq(2)
      expect(body['faltosos']).to eq(1)
      expect(body['frequencias']).to eq(4)
      expect(body['turno']).to eq('matutino')
    end

    it 'includes integral classrooms in the morning and afternoon searches' do
      integral = create(:classroom, unity: unity, year: data.year, period: Periods::FULL)
      launch_frequency(integral, Periods::MATUTINAL, present_student, true)

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'matutino', locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['presentes']).to eq(1)

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'vespertino', locale: 'pt-BR' }

      expect(JSON.parse(response.body)['presentes']).to eq(1)

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'noturno', locale: 'pt-BR' }

      expect(JSON.parse(response.body)['presentes']).to eq(0)
      expect(JSON.parse(response.body)['faltosos']).to eq(0)
    end

    it 'counts only nighttime classrooms when the search is nighttime' do
      noite = create(:classroom, unity: unity, year: data.year, period: Periods::NIGHTLY)
      tarde = create(:classroom, unity: unity, year: data.year, period: Periods::VESPERTINE)
      launch_frequency(noite, Periods::NIGHTLY, present_student, true)
      launch_frequency(tarde, Periods::VESPERTINE, absent_student, false)

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'noturno', locale: 'pt-BR' }

      body = JSON.parse(response.body)
      expect(body['presentes']).to eq(1)
      expect(body['faltosos']).to eq(0)

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'vespertino', locale: 'pt-BR' }

      body = JSON.parse(response.body)
      expect(body['presentes']).to eq(0)
      expect(body['faltosos']).to eq(1)
    end

    it 'rejects an unknown token' do
      request.headers['token'] = 'token-diferente'

      get :show, params: { cod_escola: unity.api_code, data: data.iso8601, turno: 'matutino' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns an error when the school does not exist' do
      get :show, params: { cod_escola: 'inexistente', data: data.iso8601, turno: 'matutino', locale: 'pt-BR' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors']).to include('Escola não encontrada')
    end
  end
end
