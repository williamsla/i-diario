require 'rails_helper'

RSpec.describe ObservationDiaryRecordsController, type: :controller do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  let(:unity) { create(:unity) }
  let(:current_teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:school_calendar) {
    create(
      :school_calendar,
      :with_trimester_steps,
      unity: unity
    )
  }

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

  let(:classroom) {
    create(
      :classroom,
      :score_type_numeric,
      :with_teacher_discipline_classroom,
      teacher: current_teacher,
      discipline: discipline,
      school_calendar: school_calendar,
      year: school_calendar.year,
      unity: unity
    )
  }

  let(:observation_diary_record) {
    create(
      :observation_diary_record,
      :with_notes,
      teacher: current_teacher,
      classroom: classroom,
      discipline: discipline,
      school_calendar: school_calendar,
    )
  }

  let(:another_observation_diary_record) {
    create(
      :observation_diary_record,
      :with_notes,
      teacher: current_teacher,
      classroom: classroom,
      discipline: discipline,
      school_calendar: school_calendar,
      date: Date.current - 1.week
    )
  }

  let(:params) {
    {
      locale: 'pt-BR',
      format: 'json',
      observation_diary_record: {
        discipline_id: discipline.id,
        classroom_id: classroom,
        unity_id: unity.id,
        school_calendar_id: school_calendar.id,
        teacher_id: current_teacher.id,
        date: observation_diary_record.date,
        notes_attributes: {
          "0": {
            id: observation_diary_record.notes.first.id,
            description: 'test',
            student_ids: []
          }
        }
      }
    }
  }

  before(:each) do
    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    request.env['REQUEST_PATH'] = '/observation_diary_records'
  end

  describe 'GET observation_diary_records#index' do
    context 'without filter' do
      before do
        get :index, params: { locale: 'pt-BR' }
      end

      it 'lists all records' do
        expect(assigns(:observation_diary_records)).to include(observation_diary_record)
      end
    end

    context 'with discipline filter' do
      context 'when the discipline exists' do
        before do
          get :index, params: { locale: 'pt-BR', filter: { by_discipline: discipline.id } }
        end

        it 'lists the records by discipline' do
          expect(assigns(:observation_diary_records)).to eq([observation_diary_record])
        end
      end

      context 'without discipline' do
        let(:nil_discipline) { nil }

        before do
          get :index, params: { locale: 'pt-BR', filter: { by_discipline: nil_discipline } }
        end

        it 'lists all records' do
          expect(assigns(:observation_diary_records))
            .to include(observation_diary_record, another_observation_diary_record)
        end
      end
    end

    context 'when filtering students by profile' do
      let(:student) { create(:student) }
      let(:same_school_student) { create(:student) }
      let(:other_school_student) { create(:student) }

      let(:same_school_other_classroom) {
        create(
          :classroom,
          :score_type_numeric,
          school_calendar: school_calendar,
          year: school_calendar.year,
          unity: unity
        )
      }

      let(:other_unity) { create(:unity) }
      let(:other_school_calendar) {
        create(:school_calendar, :with_trimester_steps, unity: other_unity)
      }
      let(:other_school_classroom) {
        create(
          :classroom,
          :score_type_numeric,
          school_calendar: other_school_calendar,
          year: other_school_calendar.year,
          unity: other_unity
        )
      }

      let(:same_school_other_classroom_record) {
        create_record_with_student(
          classroom: same_school_other_classroom,
          student: same_school_student,
          school_calendar: school_calendar
        )
      }

      let(:other_school_record) {
        create_record_with_student(
          classroom: other_school_classroom,
          student: other_school_student,
          school_calendar: other_school_calendar
        )
      }

      before do
        add_student_to_record(observation_diary_record, student)
        same_school_other_classroom_record
        other_school_record
      end

      context 'when the current role is teacher' do
        before do
          get :index, params: { locale: 'pt-BR' }
        end

        it 'lists only records from the classroom selected in the profile' do
          expect(assigns(:observation_diary_records)).to include(observation_diary_record)
          expect(assigns(:observation_diary_records)).not_to include(
            same_school_other_classroom_record,
            other_school_record
          )
        end

        it 'lists only students from the classroom selected in the profile' do
          expect(assigns(:students)).to include(student)
          expect(assigns(:students)).not_to include(same_school_student, other_school_student)
        end
      end

      context 'when the current role is administrator' do
        let(:admin_user) do
          create(
            :user,
            :with_user_role_administrator,
            admin: false,
            teacher_id: current_teacher.id,
            current_unity_id: unity.id,
            current_school_year: classroom.year,
            current_classroom_id: classroom.id,
            current_discipline_id: discipline.id
          )
        end

        before do
          sign_in(admin_user)
          get :index, params: { locale: 'pt-BR' }
        end

        it 'lists records from all classrooms of the current school' do
          expect(assigns(:observation_diary_records)).to include(
            observation_diary_record,
            same_school_other_classroom_record
          )
          expect(assigns(:observation_diary_records)).not_to include(other_school_record)
        end

        it 'lists students from all classrooms of the current school' do
          expect(assigns(:students)).to include(student, same_school_student)
          expect(assigns(:students)).not_to include(other_school_student)
        end
      end

      context 'when the current role is employee' do
        let(:employee_user) { create_employee_user }

        before do
          sign_in(employee_user)
          get :index, params: { locale: 'pt-BR' }
        end

        it 'lists records from all classrooms of the current school' do
          expect(assigns(:observation_diary_records)).to include(
            observation_diary_record,
            same_school_other_classroom_record
          )
          expect(assigns(:observation_diary_records)).not_to include(other_school_record)
        end

        it 'lists students from all classrooms of the current school' do
          expect(assigns(:students)).to include(student, same_school_student)
          expect(assigns(:students)).not_to include(other_school_student)
        end
      end
    end
  end

  describe 'PATCH discipline_teaching_plans#update' do
    context 'when a record does not have a discipline' do
      it 'allows to save a new discipline' do
        allow(observation_diary_record).to receive(:can_update?).and_return(true)
        observation_diary_record.update(discipline_id: nil)

        params[:observation_diary_record][:discipline_id] = discipline.id
        params[:id] = observation_diary_record.id
        request.headers['CONTENT_TYPE'] = 'application/json'
        patch :update, params: params.merge(params)
        expect(ObservationDiaryRecord.find(observation_diary_record.id).discipline_id).to eq(discipline.id)
      end
    end
  end

  def add_student_to_record(record, student)
    create(
      :observation_diary_record_note_student,
      observation_diary_record_note: record.notes.first,
      student: student
    )
  end

  def create_record_with_student(classroom:, student:, school_calendar:)
    record = create(
      :observation_diary_record,
      :with_notes,
      teacher: current_teacher,
      classroom: classroom,
      discipline: discipline,
      school_calendar: school_calendar
    )
    add_student_to_record(record, student)
    record
  end

  def create_employee_user
    employee = create(
      :user,
      admin: false,
      teacher_id: current_teacher.id,
      current_unity_id: unity.id,
      current_school_year: classroom.year,
      current_classroom_id: classroom.id,
      current_discipline_id: discipline.id
    )
    user_role = create(
      :user_role,
      user: employee,
      role: create(:role, access_level: AccessLevel::EMPLOYEE),
      unity: unity
    )
    employee.update!(current_user_role: user_role)
    employee
  end
end
