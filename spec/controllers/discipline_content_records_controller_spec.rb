require 'spec_helper'

RSpec.describe DisciplineContentRecordsController, type: :controller do
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
  let(:content) { create(:content) }

  let(:params) {
    {
      locale: 'pt-BR',
      discipline_content_record: {
        discipline_id: discipline.id,
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
                              RequireDailyActivitiesRecordTypes::ON_DISCIPLINE_CONTENT_RECORDS
                          )
    end

    it 'not having a daily activities record fails to create and renders the new template' do
      params[:discipline_content_record][:content_record_attributes].delete(:daily_activities_record)
      post :create, params: params.merge(params)
      expect(response).to render_template(:new)
    end

    it 'having a daily activities record creates and redirects to discipline content records path' do
      post :create, params: params
      expect(response).to redirect_to(discipline_content_records_path)
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

    it 'not having a daily activities record creates and redirects to discipline content records path' do
      params[:discipline_content_record][:content_record_attributes].delete(:daily_activities_record)
      post :create, params: params.merge(params)
      expect(response).to redirect_to(discipline_content_records_path)
    end

  end

  describe 'GET #disciplines_for_record_date' do
    let(:other_teacher) { create(:teacher) }

    it 'retorna mensagem quando o professor não possui aulas no quadro para a data' do
      other_discipline = create(:discipline)
      teacher_discipline_classroom = create(
        :teacher_discipline_classroom,
        teacher: other_teacher,
        classroom: classroom,
        discipline: other_discipline,
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

      get :disciplines_for_record_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: '28/02/2017'
      }

      payload = JSON.parse(response.body)

      expect(payload['disciplines']).to be_empty
      expect(payload['message']).to include('quadro de horários')
    end

    it 'libera a disciplina quando ela consta no quadro mesmo com outro professor alocado' do
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

      get :disciplines_for_record_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: '28/02/2017'
      }

      payload = JSON.parse(response.body)
      discipline_ids = payload['disciplines'].map { |item| item['id'] }

      expect(discipline_ids).to include(discipline.id)
      expect(payload['message']).to be_nil
    end

    it 'retorna todas as disciplinas em sábado letivo sem dia equivalente cadastrado' do
      saturday = Date.parse('2017-06-10')
      create(
        :school_calendar_event,
        school_calendar: school_calendar,
        coverage: EventCoverageType::BY_UNITY,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: nil,
        periods: Periods.list
      )

      get :disciplines_for_record_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: saturday.strftime('%d/%m/%Y')
      }

      payload = JSON.parse(response.body)
      discipline_ids = payload['disciplines'].map { |item| item['id'] }

      expect(discipline_ids).to include(discipline.id)
      expect(payload['message']).to be_nil
    end

    it 'libera a data quando há reposição cadastrada mesmo sem aulas no quadro' do
      other_discipline = create(:discipline)
      teacher_discipline_classroom = create(
        :teacher_discipline_classroom,
        teacher: other_teacher,
        classroom: classroom,
        discipline: other_discipline,
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
      TeacherAbsence.create!(
        unity: unity,
        classroom: classroom,
        discipline: discipline,
        school_calendar: school_calendar,
        teacher: current_teacher,
        user: user,
        absence_date: Date.parse('2017-02-20'),
        reason: 'Falta',
        will_make_up: true,
        make_up_date: Date.parse('2017-02-28'),
        coverage: TeacherAbsenceCoverage::BY_CLASSROOM
      )

      get :disciplines_for_record_date, params: {
        locale: 'pt-BR',
        classroom_id: classroom.id,
        record_date: '28/02/2017'
      }

      payload = JSON.parse(response.body)
      discipline_ids = payload['disciplines'].map { |item| item['id'] }

      expect(discipline_ids).to include(discipline.id)
      expect(payload['message']).to be_nil
    end
  end
end
