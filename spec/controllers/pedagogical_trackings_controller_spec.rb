require 'rails_helper'

RSpec.describe PedagogicalTrackingsController, type: :controller do
  render_views

  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:year) { Date.current.year }
  let(:unity) { create(:unity) }
  let(:other_unity) { create(:unity) }
  let(:course) { create(:course, description: 'Ensino Fundamental') }
  let(:infantil_course) { create(:course, description: 'Educação Infantil - Creche') }
  let(:grade) { create(:grade, course: course, description: '1º ANO') }
  let(:infantil_grade) { create(:grade, course: infantil_course, description: 'BERÇÁRIO') }
  let(:other_grade) { create(:grade, course: course, description: '2º ANO') }
  let(:classroom) { create(:classroom, unity: unity, year: year) }
  let(:infantil_classroom) { create(:classroom, unity: unity, year: year) }
  let(:other_classroom) { create(:classroom, unity: other_unity, year: year) }
  let(:teacher) { create(:teacher) }
  let(:knowledge_area) { create(:knowledge_area, description: 'Matemática') }
  let(:discipline) { create(:discipline, knowledge_area: knowledge_area, description: 'Matemática') }
  let(:content) { create(:content, description: 'Adição de frações') }
  let(:knowledge_area_content) { create(:content, description: 'Contagem com material concreto') }
  let(:user) do
    create(
      :user,
      admin: true,
      current_unity_id: unity.id,
      current_school_year: year
    )
  end

  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  before do
    create(:classrooms_grade, classroom: classroom, grade: grade)
    create(:classrooms_grade, classroom: infantil_classroom, grade: infantil_grade)
    create(:classrooms_grade, classroom: other_classroom, grade: other_grade)
    create(:school_calendar, :with_one_step, unity: unity, year: year)
    create(:school_calendar, :with_one_step, unity: other_unity, year: year)
    create(
      :teacher_discipline_classroom,
      classroom: classroom,
      teacher: teacher,
      discipline: discipline,
      grade: grade,
      year: year
    )
    create(
      :teacher_discipline_classroom,
      classroom: infantil_classroom,
      teacher: teacher,
      discipline: discipline,
      grade: infantil_grade,
      year: year
    )

    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:current_user_school_year).and_return(year)
    request.env['REQUEST_PATH'] = ''
  end

  def create_content_record_for(target_classroom, contents)
    create(
      :content_record,
      classroom: target_classroom,
      teacher: teacher,
      record_date: Date.current,
      contents: contents
    )
  end

  describe 'series grouping' do
    it 'groups series by course, keeps the grade name clean and marks the record type' do
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [content]),
        discipline: discipline
      )

      grades = JSON.parse(
        controller.send(:grades_to_select, Grade.where(id: [grade.id, infantil_grade.id]))
      )
      group = grades.find { |item| item['children'].present? && item['text'] == course.description }

      expect(group).to be_present
      expect(group['children'].map { |item| item['text'] }).to include('1º ANO')
      expect(group['children'].map { |item| item['text'] }).not_to include('1º ANO - Ensino Fundamental')

      selected_grade = group['children'].find { |item| item['id'] == grade.id }
      expect(selected_grade['recordType']).to eq('discipline')
      expect(selected_grade['recordTypeLabel']).to eq('Disciplina')
    end
  end

  describe 'GET #tag_cloud_filters' do
    it 'returns disciplines when the grade used discipline content records' do
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [content]),
        discipline: discipline
      )

      get :tag_cloud_filters, params: { locale: 'pt-BR', grade_id: grade.id }

      payload = JSON.parse(response.body)

      expect(response).to be_successful
      expect(payload['record_type']).to eq('discipline')
      expect(payload['subject_kind']).to eq('discipline')
      expect(payload['subject_label']).to eq('Disciplina')
      expect(payload['subjects'].map { |item| item['id'] }).to include("d:#{discipline.id}")
    end

    it 'returns knowledge areas when the grade used knowledge area content records' do
      create(
        :knowledge_area_content_record,
        content_record: create_content_record_for(classroom, [knowledge_area_content]),
        knowledge_areas: [knowledge_area]
      )

      get :tag_cloud_filters, params: { locale: 'pt-BR', grade_id: grade.id }

      payload = JSON.parse(response.body)

      expect(response).to be_successful
      expect(payload['record_type']).to eq('knowledge_area')
      expect(payload['subject_kind']).to eq('knowledge_area')
      expect(payload['subject_label']).to eq('Área de conhecimento')
      expect(payload['subjects'].map { |item| item['id'] }).to include("k:#{knowledge_area.id}")
    end

    it 'returns grouped subjects when the grade used both record types' do
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [content]),
        discipline: discipline
      )
      create(
        :knowledge_area_content_record,
        content_record: create_content_record_for(classroom, [knowledge_area_content]),
        knowledge_areas: [knowledge_area]
      )

      get :tag_cloud_filters, params: { locale: 'pt-BR', grade_id: grade.id }

      payload = JSON.parse(response.body)

      expect(payload['record_type']).to eq('both')
      expect(payload['subject_kind']).to eq('both')
      expect(payload['subjects'].map { |item| item['text'] }).to include('Disciplina', 'Área de conhecimento')
    end

    it 'falls back to knowledge area for early childhood grades without records' do
      get :tag_cloud_filters, params: { locale: 'pt-BR', grade_id: infantil_grade.id }

      payload = JSON.parse(response.body)

      expect(payload['record_type']).to eq('none')
      expect(payload['subject_kind']).to eq('knowledge_area')
      expect(payload['subject_label']).to eq('Área de conhecimento')
    end

    it 'returns empty subjects for a grade the user cannot access' do
      other_user = create(
        :user_with_user_role,
        admin: false,
        current_unity_id: unity.id,
        current_school_year: year
      )
      sign_in(other_user)
      allow(controller).to receive(:current_user_school_year).and_return(year)

      get :tag_cloud_filters, params: { locale: 'pt-BR', grade_id: other_grade.id }

      payload = JSON.parse(response.body)

      expect(payload['subjects']).to eq([])
      expect(payload['record_type']).to eq('none')
    end
  end

  describe 'GET #tag_cloud_modal' do
    it 'analyzes discipline content records' do
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [content]),
        discipline: discipline
      )

      get :tag_cloud_modal, params: {
        locale: 'pt-BR',
        grade_id: grade.id,
        subject_id: "d:#{discipline.id}"
      }

      expect(response).to be_successful
      expect(response.body).to include('Adição de frações')
      expect(assigns(:tag_cloud_summary)).to include('1º ANO')
      expect(assigns(:tag_cloud_summary)).to include('Matemática')
    end

    it 'analyzes knowledge area content records' do
      create(
        :knowledge_area_content_record,
        content_record: create_content_record_for(classroom, [knowledge_area_content]),
        knowledge_areas: [knowledge_area]
      )

      get :tag_cloud_modal, params: {
        locale: 'pt-BR',
        grade_id: grade.id,
        subject_id: "k:#{knowledge_area.id}"
      }

      expect(response).to be_successful
      expect(response.body).to include('Contagem com material concreto')
      expect(response.body).not_to include('Adição de frações')
    end

    it 'keeps backward compatibility with numeric discipline_id' do
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [content]),
        discipline: discipline
      )

      get :tag_cloud_modal, params: {
        locale: 'pt-BR',
        grade_id: grade.id,
        discipline_id: discipline.id
      }

      expect(response).to be_successful
      expect(response.body).to include('Adição de frações')
    end

    it 'returns bad request when grade or subject is missing' do
      get :tag_cloud_modal, params: { locale: 'pt-BR', grade_id: grade.id }

      expect(response).to have_http_status(:bad_request)
    end

    it 'does not mix knowledge area contents into a discipline analysis' do
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [content]),
        discipline: discipline
      )
      create(
        :knowledge_area_content_record,
        content_record: create_content_record_for(classroom, [knowledge_area_content]),
        knowledge_areas: [knowledge_area]
      )

      get :tag_cloud_modal, params: {
        locale: 'pt-BR',
        grade_id: grade.id,
        subject_id: "d:#{discipline.id}"
      }

      expect(response.body).to include('Adição de frações')
      expect(response.body).not_to include('Contagem com material concreto')
    end
  end
end
