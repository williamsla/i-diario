require 'rails_helper'

RSpec.describe Api::V2::MonthlyAbsenceByStudentReportsController, type: :controller do
  describe 'GET #report' do
    let(:unity) { create(:unity, api_code: '99999') }
    let(:classroom) { create(:classroom, unity: unity) }
    let(:student) { create(:student) }
    let(:school_calendar) { create(:school_calendar, unity: unity, year: 2026) }
    let(:configuration) { create(:ieducar_api_configuration) }

    let!(:daily_frequency) do
      create(
        :daily_frequency,
        unity: unity,
        classroom: classroom,
        school_calendar: school_calendar,
        frequency_date: Date.new(2026, 2, 5)
      )
    end

    let!(:absence) do
      create(
        :daily_frequency_student,
        daily_frequency: daily_frequency,
        student: student,
        present: false,
        active: true
      )
    end

    around(:each) do |example|
      Entity.find_by_domain('test.host').using_connection do
        example.run
      end
    end

    before do
      request.env['REQUEST_PATH'] = '/api/v2/monthly_absence_by_student_reports/report'
      request.headers['token'] = configuration.api_security_token
    end

    it 'returns pdf when params are valid' do
      get :report, params: {
        cod_escola: unity.api_code,
        ano: 2026,
        meses: '2',
        locale: 'pt-BR'
      }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/pdf')
    end

    it 'returns errors when school is not found' do
      get :report, params: {
        cod_escola: 'inexistente',
        ano: 2026,
        meses: '2',
        locale: 'pt-BR'
      }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['errors'].join.downcase).to include('escola não encontrada')
    end
  end
end
