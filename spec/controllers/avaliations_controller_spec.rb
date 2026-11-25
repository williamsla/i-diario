require 'rails_helper'

RSpec.describe AvaliationsController, type: :controller do
  render_views

  let(:entity) do
    record = Entity.find_by(domain: 'test.host')
    # O schema de teste local guarda hstore como texto. No banco com a extensão,
    # config já chega como Hash e este ramo não roda.
    if record.config.is_a?(String)
      parsed = YAML.safe_load(record.config).with_indifferent_access
      record.define_singleton_method(:config) { parsed }
    end
    record
  end
  let(:unity) { create(:unity) }
  let(:school_calendar) do
    create(:school_calendar, unity: unity, opened_year: true, year: Date.current.year)
  end
  let(:teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:classroom) do
    create(
      :classroom,
      :with_classroom_semester_steps,
      unity: unity,
      year: school_calendar.year,
      school_calendar: school_calendar
    )
  end
  let(:user) do
    create(
      :user_with_user_role,
      admin: false,
      teacher_id: teacher.id,
      current_unity_id: unity.id,
      current_school_year: classroom.year,
      current_classroom_id: classroom.id,
      current_discipline_id: discipline.id
    )
  end

  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  before do
    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:current_user_classroom).and_return(classroom)
    allow(controller).to receive(:current_user_discipline).and_return(discipline)
    allow(controller).to receive(:current_teacher).and_return(teacher)
    allow(controller).to receive(:current_unity).and_return(unity)
    request.env['REQUEST_PATH'] = '/avaliacoes'
  end

  describe 'GET #index' do
    it 'lista as etapas com o preenchimento e conserva o lançamento e o relatório' do
      get :index, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(assigns(:classrooms)).to eq([classroom])
      expect(assigns(:disciplines)).to eq([discipline])
      expect(assigns(:exam_report_use_classroom_step_field)).to eq(true)

      steps = StepsFetcher.new(classroom).steps.to_a
      expect(assigns(:step_fill_statuses).keys).to match_array(steps.map(&:id))
      assigns(:step_fill_statuses).each_value do |status|
        expect(status.key).to eq(AvaliationStepFillStatus::NOT_STARTED)
      end

      expect(response.body).to include(I18n.t('avaliations.by_step.fill_button'))
      expect(response.body).to include(I18n.t('avaliations.by_step.fill_status.not_started'))
      expect(response.body).to include('exam_record_report_form[school_calendar_classroom_step_id]')
      expect(response.body).to include('exam_record_report_form[classroom_id]')
      expect(response.body).not_to include('exam_record_report_form[school_calendar_step_id]')
    end

    it 'mantém a resposta js sem conteúdo' do
      get :index, params: { locale: 'pt-BR' }, format: :js

      expect(response).to have_http_status(:no_content)
      expect(assigns(:step_fill_statuses)).to be_present
    end
  end
end
