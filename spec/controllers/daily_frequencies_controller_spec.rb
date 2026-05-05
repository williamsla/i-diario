require 'spec_helper'

RSpec.describe DailyFrequenciesController, type: :controller do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) do
    create(
      :user_with_user_role,
      admin: false,
      teacher_id: current_teacher.id,
      current_unity_id: unity.id,
      current_school_year: classroom.year,
      current_classroom_id: classroom.id,
      current_discipline_id: discipline.id
    )
  end
  let(:user_role) { user.user_roles.first }
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, opened_year: true) }
  let(:current_teacher) { create(:teacher) }
  let(:other_teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:grade) { create(:grade) }
  let(:classroom) {
    create(
      :classroom,
      :with_teacher_discipline_classroom,
      :with_classroom_trimester_steps,
      :score_type_numeric,
      unity: unity,
      teacher: current_teacher,
      grade: grade,
      discipline: discipline,
      school_calendar: school_calendar
    )
  }

  let(:classrooms_grade) { create(:classrooms_grade, classroom: classroom, grade: grade) }

  let(:params) {
    {
      locale: 'pt-BR',
      class_numbers: '1, 2',
      daily_frequency: {
        classroom_id: classroom.id,
        unity_id: unity.id,
        discipline_id: discipline.id,
        frequency_date: '2017-02-28',
        period: 1
      }
    }
  }

  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  before do
    user_role.unity = unity
    user_role.save!

    user.current_user_role = user_role
    user.save!

    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:current_user_is_employee_or_administrator?).and_return(false)
    allow(controller).to receive(:can_change_school_year?).and_return(true)
    allow(controller).to receive(:current_classroom).and_return(classroom)
    allow(controller).to receive(:current_teacher).and_return(current_teacher)
    allow(controller).to receive(:current_school_calendar).and_return(school_calendar)
    allow(controller).to receive(:current_teacher_id).and_return(current_teacher.id)
    request.env['REQUEST_PATH'] = ''
  end

  describe 'POST #create' do
    context 'without success' do
      it 'fails to create and renders the new template' do
        allow(school_calendar).to receive(:day_allows_entry?).and_return(false)
        post :create, params: params
        expect(response).to render_template(:new)
      end
    end

    context 'with success' do
      it 'creates and redirects to daily frequency edit page' do
        post :create, params: params
        expect(response).to redirect_to /#{edit_multiple_daily_frequencies_path}/
      end
    end

    context 'when exam rule is general but the client sends class_numbers without discipline' do
      let(:params_general_mixed) do
        {
          locale: 'pt-BR',
          class_numbers: '1,2,3,4',
          daily_frequency: {
            classroom_id: classroom.id,
            unity_id: unity.id,
            discipline_id: '',
            frequency_date: '2017-02-28',
            period: 1
          }
        }
      end

      it 'normalizes to global frequency and redirects (no frequency_type_must_be_valid)' do
        post :create, params: params_general_mixed
        expect(response).to redirect_to(/#{edit_multiple_daily_frequencies_path}/)
      end
    end
  end

  describe 'GET #edit_multiple' do
    before do
      allow(controller).to receive(:discipline_classroom_grade_ids).and_return([1, 2, classrooms_grade.grade_id])
    end

    context 'without success' do
      it 'returns not found status' do
        get :edit_multiple, params: params
        expect(response).to have_http_status(302)
      end
    end

    context 'with success' do
      it 'returns success status' do
        create(:student_enrollment_classroom, classrooms_grade: classrooms_grade)
        params[:class_numbers] = [1, 2, classrooms_grade.grade_id]
        get :edit_multiple, params: params
        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'DELETE #destroy_multiple' do
    let!(:daily_frequency_1) {
      create(
        :daily_frequency,
        :with_students,
        students_count: 3
      )
    }
    let!(:daily_frequency_2) {
      create(
        :daily_frequency,
        :with_students,
        students_count: 3
      )
    }
    let!(:daily_frequency_3) {
      create(
        :daily_frequency,
        :with_students,
        students_count: 3
      )
    }

    shared_examples 'delete_all_frequencies' do
      it 'deletes all daily_frequencies and daily_frequency_students' do
        daily_frequencies_ids = [daily_frequency_1.id, daily_frequency_2.id]

        expect {
          delete :destroy_multiple, params: { locale: 'pt-BR', daily_frequencies_ids: daily_frequencies_ids }
        }.to change(DailyFrequency, :count).by(-2)
      end
    end

    context 'when just has daily_frequencies and daily_frequency_students' do
      it_behaves_like 'delete_all_frequencies'
    end

    context 'when has discarded daily_frequency_students' do
      before do
        daily_frequency_1.students.last.discard
      end

      it_behaves_like 'delete_all_frequencies'
    end
  end

  describe 'GET #new' do
    it 'monta @daily_frequency com turma e data antes de carregar opções (evita quadro errado para o professor)' do
      get :new, params: { locale: 'pt-BR' }

      expect(assigns(:daily_frequency)).to be_a(DailyFrequency)
      expect(assigns(:daily_frequency).classroom_id).to eq(classroom.id)
      expect(assigns(:daily_frequency).frequency_date).to eq(Time.zone.today)
    end
  end

  describe 'GET #disciplines_for_frequency_date' do
    let(:other_discipline) { create(:discipline) }

    before do
      create(
        :teacher_discipline_classroom,
        teacher: current_teacher,
        classroom: classroom,
        discipline: other_discipline,
        grade: grade,
        year: classroom.year,
        allow_absence_by_discipline: 0,
        active: true
      )
      allow(classroom.classrooms_grades.first.exam_rule).to receive(:frequency_type).and_return(FrequencyTypes::GENERAL)
    end

    it 'retorna apenas disciplinas com vínculo por disciplina quando a regra da turma é geral' do
      get :disciplines_for_frequency_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        frequency_date: '2017-02-28'
      }

      payload = JSON.parse(response.body)
      discipline_ids = payload.map { |item| item['id'] }

      expect(discipline_ids).to include(discipline.id)
      expect(discipline_ids).not_to include(other_discipline.id)
    end
  end

  describe '#resolved_classroom_id_for_lessons_board (turma do formulário vs sessão)' do
    let(:other_classroom) { create(:classroom, unity: unity, year: classroom.year) }

    before do
      allow(controller).to receive(:current_user_classroom).and_return(classroom)
    end

    it 'prioriza classroom_id enviado no daily_frequency (caso típico do administrador no formulário)' do
      controller.params = ActionController::Parameters.new(
        locale: 'pt-BR',
        daily_frequency: { classroom_id: other_classroom.id }
      ).permit!

      expect(controller.send(:resolved_classroom_id_for_lessons_board)).to eq(other_classroom.id)
    end

    it 'usa a turma do @daily_frequency quando o param não traz classroom_id' do
      controller.params = ActionController::Parameters.new(locale: 'pt-BR', daily_frequency: {}).permit!
      controller.instance_variable_set(
        :@daily_frequency,
        DailyFrequency.new(classroom_id: other_classroom.id)
      )

      expect(controller.send(:resolved_classroom_id_for_lessons_board)).to eq(other_classroom.id)
    end

    it 'usa current_user_classroom quando não há turma no param nem no registro' do
      controller.params = ActionController::Parameters.new(locale: 'pt-BR', daily_frequency: {}).permit!
      controller.instance_variable_set(:@daily_frequency, DailyFrequency.new)

      expect(controller.send(:resolved_classroom_id_for_lessons_board)).to eq(classroom.id)
    end
  end

  describe '#current_frequency_type' do
    let(:daily_frequency) { DailyFrequency.new(classroom: classroom) }

    it 'retorna frequência geral quando a exam_rule da turma é geral' do
      allow(classroom.classrooms_grades.first.exam_rule).to receive(:frequency_type).and_return(FrequencyTypes::GENERAL)

      expect(controller.send(:current_frequency_type, daily_frequency)).to eq(FrequencyTypes::GENERAL)
    end
  end

  describe '#frequency_discipline_id_for_link_validation' do
    let(:other_discipline) { create(:discipline) }

    it 'prioriza a disciplina selecionada no formulário mesmo quando o tipo calculado é geral' do
      controller.params = ActionController::Parameters.new(
        locale: 'pt-BR',
        daily_frequency: { discipline_id: other_discipline.id }
      ).permit!
      allow(controller).to receive(:frequency_type_for_classroom_and_discipline).and_return(FrequencyTypes::GENERAL)

      result = controller.send(:frequency_discipline_id_for_link_validation, classroom)

      expect(result).to eq(other_discipline.id)
    end

    it 'usa a disciplina do perfil quando a disciplina do formulário está em branco' do
      controller.params = ActionController::Parameters.new(
        locale: 'pt-BR',
        daily_frequency: { discipline_id: '' }
      ).permit!
      allow(controller).to receive(:frequency_type_for_classroom_and_discipline).and_return(FrequencyTypes::GENERAL)

      result = controller.send(:frequency_discipline_id_for_link_validation, classroom)

      expect(result).to eq(discipline.id)
    end
  end

  describe '#frequency_type_for_classroom_and_discipline' do
    before do
      allow(controller).to receive(:current_teacher).and_return(current_teacher)
      allow(classroom.classrooms_grades.first.exam_rule).to receive(:frequency_type).and_return(FrequencyTypes::GENERAL)
    end

    it 'retorna por disciplina quando o vínculo da disciplina é de área específica' do
      result = controller.send(
        :frequency_type_for_classroom_and_discipline,
        classroom: classroom,
        discipline_id: discipline.id
      )

      expect(result).to eq(FrequencyTypes::BY_DISCIPLINE)
    end

    it 'retorna por disciplina quando regra da turma é por disciplina mesmo sem vínculo específico' do
      TeacherDisciplineClassroom.where(
        teacher_id: current_teacher.id,
        classroom_id: classroom.id,
        discipline_id: discipline.id
      ).update_all(allow_absence_by_discipline: 0)
      allow(classroom.classrooms_grades.first.exam_rule).to receive(:frequency_type).and_return(FrequencyTypes::BY_DISCIPLINE)

      result = controller.send(
        :frequency_type_for_classroom_and_discipline,
        classroom: classroom,
        discipline_id: discipline.id
      )

      expect(result).to eq(FrequencyTypes::BY_DISCIPLINE)
    end

    it 'retorna geral quando não há vínculo específico e regra da turma é geral' do
      TeacherDisciplineClassroom.where(
        teacher_id: current_teacher.id,
        classroom_id: classroom.id,
        discipline_id: discipline.id
      ).update_all(allow_absence_by_discipline: 0)

      result = controller.send(
        :frequency_type_for_classroom_and_discipline,
        classroom: classroom,
        discipline_id: discipline.id
      )

      expect(result).to eq(FrequencyTypes::GENERAL)
    end
  end
end
