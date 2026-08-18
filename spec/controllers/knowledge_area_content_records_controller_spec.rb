require 'spec_helper'

RSpec.describe KnowledgeAreaContentRecordsController, type: :controller do
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
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, opened_year: true) }
  let(:current_teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:classroom) {
    create(
      :classroom,
      :with_teacher_discipline_classroom,
      :with_classroom_trimester_steps,
      :score_type_numeric,
      unity: unity,
      teacher: current_teacher,
      discipline: discipline,
      school_calendar: school_calendar
    )
  }
  let(:knowledge_area) { create(:knowledge_area) }
  let(:content) { create(:content) }

  let(:params) {
    {
      locale: 'pt-BR',
      knowledge_area_content_record: {
        knowledge_area_ids: knowledge_area.id.to_s,
        content_record_attributes: {
          classroom_id: classroom.id,
          unity_id: unity.id,
          daily_activities_record: 'test',
          record_date: '2017-02-28',
          content_ids: [content.id]
        }
      }
    }
  }

  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  before do
    sign_in(user)
    knowledge_area.disciplines << discipline
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:current_teacher).and_return(current_teacher)
    allow(controller).to receive(:current_teacher_id).and_return(current_teacher.id)
    request.env['REQUEST_PATH'] = ''
  end

  describe 'POST #create when daily activities record is required' do
    before(:each) do
      GeneralConfiguration.current
                          .update(
                            require_daily_activities_record:
                              RequireDailyActivitiesRecordTypes::ON_KNOWLEDGE_AREA_CONTENT_RECORDS
                          )
    end

    it 'not having a daily activities record fails to create and renders the new template' do
      params[:knowledge_area_content_record][:content_record_attributes].delete(:daily_activities_record)
      post :create, params: params.merge(params)
      expect(response).to render_template(:new)
    end

    it 'having a daily activities record creates and redirects to knowledge area  content records path' do
      post :create, params: params
      expect(response).to redirect_to(knowledge_area_content_records_path)
    end

  end

  describe 'POST #create when daily activities record is not required' do
    before(:each) do
      GeneralConfiguration.current
                          .update(
                            require_daily_activities_record:
                              RequireDailyActivitiesRecordTypes::DOES_NOT_REQUIRE
                          )
    end

    it 'not having a daily activities record creates and redirects to knowledge area content records path' do
      params[:knowledge_area_content_record][:content_record_attributes].delete(:daily_activities_record)
      post :create, params: params.merge(params)
      expect(response).to redirect_to(knowledge_area_content_records_path)
    end

  end

  describe 'GET #knowledge_areas_for_record_date' do
    let(:other_teacher) { create(:teacher) }

    it 'retorna mensagem quando não há aulas no quadro para o dia da semana' do
      classrooms_grade = classroom.classrooms_grades.first
      lessons_board = create(:lessons_board, classrooms_grade: classrooms_grade)
      lesson = create(:lessons_board_lesson, lessons_board: lessons_board, lesson_number: 1)
      create(
        :lessons_board_lesson_weekday,
        lessons_board_lesson: lesson,
        teacher_discipline_classroom: classroom.teacher_discipline_classrooms.first,
        weekday: :monday
      )

      get :knowledge_areas_for_record_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: '28/02/2017'
      }

      payload = JSON.parse(response.body)

      expect(payload['knowledge_areas']).to be_empty
      expect(payload['message']).to include('quadro de horários')
    end

    it 'libera as áreas quando a disciplina da área consta no quadro mesmo com outro professor alocado' do
      teacher_discipline_classroom = create(
        :teacher_discipline_classroom,
        teacher: other_teacher,
        classroom: classroom,
        discipline: discipline,
        grade: classroom.classrooms_grades.first.grade,
        year: classroom.year,
        active: true
      )
      classrooms_grade = classroom.classrooms_grades.first
      lessons_board = create(:lessons_board, classrooms_grade: classrooms_grade)
      lesson = create(:lessons_board_lesson, lessons_board: lessons_board, lesson_number: 1)
      create(
        :lessons_board_lesson_weekday,
        lessons_board_lesson: lesson,
        teacher_discipline_classroom: teacher_discipline_classroom,
        weekday: :tuesday
      )

      get :knowledge_areas_for_record_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: '28/02/2017'
      }

      payload = JSON.parse(response.body)
      knowledge_area_ids = payload['knowledge_areas'].map { |item| item['id'] }

      expect(knowledge_area_ids).to include(knowledge_area.id)
      expect(payload['message']).to be_nil
    end
  end

  describe 'GET #find_existing' do
    let(:other_teacher) { create(:teacher) }
    let(:record_date) { Date.new(2017, 2, 28) }

    def create_knowledge_area_content_record_for(teacher)
      content_record = build(
        :content_record,
        :with_contents,
        classroom: classroom,
        teacher: teacher,
        record_date: record_date
      )
      content_record.save!(validate: false)

      record = KnowledgeAreaContentRecord.new(content_record: content_record)
      record.save!(validate: false)
      record.knowledge_areas << knowledge_area
      record
    end

    it 'não devolve registro de outro professor da mesma turma, data e área' do
      create_knowledge_area_content_record_for(other_teacher)

      get :find_existing, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: record_date.to_s,
        knowledge_area_ids: [knowledge_area.id]
      }

      expect(JSON.parse(response.body)['id']).to be_nil
    end

    it 'devolve o registro do professor atual mesmo com registro de outro professor no mesmo dia' do
      current_record = create_knowledge_area_content_record_for(current_teacher)
      create_knowledge_area_content_record_for(other_teacher)

      get :find_existing, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: record_date.to_s,
        knowledge_area_ids: [knowledge_area.id]
      }

      expect(JSON.parse(response.body)['id']).to eq(current_record.id)
    end
  end
end
