require 'rails_helper'

RSpec.describe AeeCaseStudiesController, type: :controller do
  render_views

  let(:entity) { Entity.find_by(domain: 'test.host') }
  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, opened_year: true) }
  let(:current_teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:classroom) do
    create(
      :classroom,
      unity: unity,
      year: school_calendar.year,
      description: 'Turma AEE'
    )
  end
  let(:student) { create(:student, birth_date: Date.current - 11.years - 1.month) }
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

  let(:valid_attributes) do
    {
      student_id: student.id,
      identification: 'Deficiência intelectual',
      individual_demands: 'Demandas',
      barriers_and_context: 'Barreiras',
      potentialities_and_support: 'Potencialidades',
      accessibility_strategies: 'Estratégias',
      final_considerations: 'Considerações',
      document_date: Date.current
    }
  end

  before do
    create_regular_enrollment
    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:is_aee).and_return(true)
    allow(controller).to receive(:current_user_classroom).and_return(classroom)
    allow(controller).to receive(:current_teacher).and_return(current_teacher)
    allow(controller).to receive(:current_teacher_id).and_return(current_teacher.id)
    allow(controller).to receive(:current_unity).and_return(unity)
    allow(controller).to receive(:current_school_calendar).and_return(school_calendar)
    allow(StudentEnrollmentsList).to receive(:new).and_return(
      double(student_enrollments: [double(student_id: student.id)])
    )
    request.env['REQUEST_PATH'] = '/estudos-de-caso-aee'
  end

  describe 'GET #index' do
    it 'lists studies of the current classroom and year' do
      matching = create(
        :aee_case_study,
        classroom: classroom,
        unity: unity,
        school_calendar: school_calendar,
        year: classroom.year,
        teacher: current_teacher,
        user: user,
        student: student
      )
      other = create(:aee_case_study, unity: unity, year: classroom.year)

      get :index, params: { locale: 'pt-BR' }

      expect(assigns(:aee_case_studies)).to include(matching)
      expect(assigns(:aee_case_studies)).not_to include(other)
    end

    it 'redirects to root when the classroom is not AEE' do
      allow(controller).to receive(:is_aee).and_return(false)

      get :index, params: { locale: 'pt-BR' }

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'GET #new' do
    it 'renders the form without age, grade and modality inputs' do
      get :new, params: { locale: 'pt-BR' }

      expect(response).to be_success
      expect(response.body).to include('id="aee-student-summary"')
      expect(response.body).not_to include('id="aee_case_study_age"')
      expect(response.body).not_to include('id="aee_case_study_grade_stage"')
      expect(response.body).not_to include('id="aee_case_study_modality"')
    end
  end

  describe 'POST #create' do
    it 'creates the study and redirects to the index' do
      expect {
        post :create, params: { locale: 'pt-BR', aee_case_study: valid_attributes }
      }.to change(AeeCaseStudy, :count).by(1)

      created = AeeCaseStudy.last
      expect(created.classroom).to eq(classroom)
      expect(created.grade_stage).to eq('3º Ano')
      expect(created.modality).to eq('Ensino Fundamental')
      expect(created.age).to eq('11 anos')
      expect(response).to redirect_to(aee_case_studies_path)
    end

    it 'ignores grade and modality sent in the request' do
      post :create, params: {
        locale: 'pt-BR',
        aee_case_study: valid_attributes.merge(
          grade_stage: 'HACK',
          modality: 'HACK'
        )
      }

      created = AeeCaseStudy.last
      expect(created.grade_stage).to eq('3º Ano')
      expect(created.modality).to eq('Ensino Fundamental')
    end

    it 'renders new when the study is invalid' do
      post :create, params: {
        locale: 'pt-BR',
        aee_case_study: valid_attributes.merge(individual_demands: '')
      }

      expect(response).to render_template(:new)
    end
  end

  describe 'PUT #update' do
    let!(:record) do
      create(
        :aee_case_study,
        classroom: classroom,
        unity: unity,
        school_calendar: school_calendar,
        year: classroom.year,
        teacher: current_teacher,
        user: user,
        student: student
      )
    end

    it 'updates the study and redirects to the index' do
      put :update, params: {
        locale: 'pt-BR',
        id: record.id,
        aee_case_study: valid_attributes.merge(identification: 'Texto revisado')
      }

      expect(record.reload.identification).to eq('Texto revisado')
      expect(response).to redirect_to(aee_case_studies_path)
    end
  end

  describe 'DELETE #destroy' do
    let!(:record) do
      create(
        :aee_case_study,
        classroom: classroom,
        unity: unity,
        school_calendar: school_calendar,
        year: classroom.year,
        teacher: current_teacher,
        user: user,
        student: student
      )
    end

    it 'destroys the study and redirects to the index' do
      expect {
        delete :destroy, params: { locale: 'pt-BR', id: record.id }
      }.to change(AeeCaseStudy, :count).by(-1)

      expect(response).to redirect_to(aee_case_studies_path)
    end
  end

  describe 'GET #show' do
    let!(:record) do
      create(
        :aee_case_study,
        classroom: classroom,
        unity: unity,
        school_calendar: school_calendar,
        year: classroom.year,
        teacher: current_teacher,
        user: user,
        student: student
      )
    end

    it 'builds the pdf' do
      expect(controller).to receive(:send_pdf) do |prefix, pdf|
        expect(prefix).to eq(I18n.t('routes.aee_case_study'))
        expect(pdf).to be_present
        controller.head :ok
      end

      get :show, params: { locale: 'pt-BR', id: record.id }
    end
  end

  describe 'GET #student_data' do
    it 'returns age, identification, grade and modality' do
      deficiency = create(:deficiency, name: 'Deficiência intelectual')
      create(:deficiency_student, student: student, deficiency: deficiency)

      get :student_data, params: { locale: 'pt-BR', student_id: student.id, format: :json }

      body = JSON.parse(response.body)
      expect(body['age']).to eq('11 anos')
      expect(body['identification']).to eq('Deficiência intelectual')
      expect(body['grade_stage']).to eq('3º Ano')
      expect(body['modality']).to eq('Ensino Fundamental')
    end

    it 'returns an empty object when the student is not in the classroom' do
      get :student_data, params: { locale: 'pt-BR', student_id: create(:student).id, format: :json }

      expect(JSON.parse(response.body)).to eq({})
    end
  end

  def create_regular_enrollment
    course = create(:course, description: 'Ensino Fundamental')
    grade = create(:grade, course: course, description: '3º Ano')
    regular_classroom = create(:classroom, year: classroom.year, unity: unity, description: '3º Ano A')
    classrooms_grade = create(:classrooms_grade, classroom: regular_classroom, grade: grade)
    enrollment = create(:student_enrollment, student: student)
    create(:student_enrollment_classroom, student_enrollment: enrollment, classrooms_grade: classrooms_grade)
  end
end
