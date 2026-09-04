require 'spec_helper'

RSpec.describe ConceptualExamsController, type: :controller do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, opened_year: true) }
  let(:step) { school_calendar.steps.first }
  let(:current_teacher) { create(:teacher) }
  let(:other_teacher) { create(:teacher) }
  let(:teacher_discipline) { create(:discipline) }
  let(:other_discipline) { create(:discipline) }
  let(:exam_rule) { create(:exam_rule, :score_type_concept) }
  let(:grade) { create(:grade) }
  let(:classroom) do
    create(:classroom, unity: unity, year: school_calendar.year)
  end
  let(:classrooms_grade) do
    create(:classrooms_grade, classroom: classroom, grade: grade, exam_rule: exam_rule)
  end
  let(:student) { create(:student) }
  let(:student_enrollment) { create(:student_enrollment, student: student) }
  let(:user) do
    create(
      :user_with_user_role,
      admin: false,
      teacher_id: current_teacher.id,
      current_unity_id: unity.id,
      current_school_year: classroom.year,
      current_classroom_id: classroom.id,
      current_discipline_id: teacher_discipline.id
    )
  end

  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  before do
    classrooms_grade
    create(
      :student_enrollment_classroom,
      classrooms_grade: classrooms_grade,
      student_enrollment: student_enrollment
    )
    create(
      :teacher_discipline_classroom,
      classroom: classroom,
      teacher: current_teacher,
      discipline: teacher_discipline,
      grade: grade,
      year: classroom.year,
      score_type: ScoreTypes::CONCEPT
    )
    create(
      :teacher_discipline_classroom,
      classroom: classroom,
      teacher: other_teacher,
      discipline: other_discipline,
      grade: grade,
      year: classroom.year,
      score_type: ScoreTypes::CONCEPT
    )
    create(
      :school_calendar_discipline_grade,
      school_calendar: school_calendar,
      discipline: teacher_discipline,
      grade: grade
    )
    create(
      :school_calendar_discipline_grade,
      school_calendar: school_calendar,
      discipline: other_discipline,
      grade: grade
    )

    GeneralConfiguration.current.update!(conceptual_exam_batch_layout: true)

    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:current_user_classroom).and_return(classroom)
    allow(controller).to receive(:current_teacher).and_return(current_teacher)
    allow(controller).to receive(:current_teacher_id).and_return(current_teacher.id)
    allow(controller).to receive(:current_unity).and_return(unity)
    allow(controller).to receive(:current_school_calendar).and_return(school_calendar)
    allow(controller).to receive(:current_user_discipline).and_return(teacher_discipline)
    allow(controller).to receive(:can_launch_in_step?).and_return(true)
    allow(StudentEnrollmentsList).to receive(:new).and_return(
      double(student_enrollments: [double(student_id: student.id, exempted_disciplines: nil)])
    )
    request.env['REQUEST_PATH'] = ''
  end

  describe 'GET #form_batch' do
    let(:params) do
      {
        locale: 'pt-BR',
        conceptual_exam_batch: {
          unity_id: unity.id,
          classroom_id: classroom.id,
          step_id: step.id
        }
      }
    end

    it 'lists only the current teacher disciplines when creating a new batch' do
      get :form_batch, params: params

      expect(response).to render_template(:form_batch)
      expect(assigns(:disciplines).map(&:id)).to contain_exactly(teacher_discipline.id)
    end

    it 'lists only the current teacher disciplines when editing an existing exam' do
      exam = ConceptualExam.new(
        classroom: classroom,
        student: student,
        recorded_at: step.start_at,
        step_number: step.step_number,
        unity_id: unity.id
      )
      exam.save!(validate: false)
      create(:conceptual_exam_value, conceptual_exam: exam, discipline: teacher_discipline, value: 1)
      create(:conceptual_exam_value, conceptual_exam: exam, discipline: other_discipline, value: 2)

      get :form_batch, params: params

      expect(response).to render_template(:form_batch)
      expect(assigns(:disciplines).map(&:id)).to contain_exactly(teacher_discipline.id)
      expect(assigns(:disciplines_by_student)[student.id]).to contain_exactly(teacher_discipline.id)
    end
  end

  describe 'POST #create_batch' do
    it 'updates only the current teacher disciplines and keeps other disciplines unchanged' do
      exam = ConceptualExam.new(
        classroom: classroom,
        student: student,
        recorded_at: step.start_at,
        step_number: step.step_number,
        unity_id: unity.id
      )
      exam.save!(validate: false)
      teacher_value = create(:conceptual_exam_value, conceptual_exam: exam, discipline: teacher_discipline, value: 3)
      other_value = create(:conceptual_exam_value, conceptual_exam: exam, discipline: other_discipline, value: 8)
      other_updated_at = other_value.updated_at

      allow(controller).to receive(:allow_teacher_modify_prev_years)

      post :create_batch, params: {
        locale: 'pt-BR',
        conceptual_exam_batch: {
          unity_id: unity.id,
          classroom_id: classroom.id,
          step_id: step.id,
          recorded_at: step.end_at,
          students: {
            student.id.to_s => {
              teacher_discipline.id.to_s => '7',
              other_discipline.id.to_s => '1'
            }
          }
        }
      }

      expect(response).to be_redirect
      expect(teacher_value.reload.value.to_d).to eq(7.to_d)
      expect(other_value.reload.value.to_d).to eq(8.to_d)
      expect(other_value.updated_at.to_i).to eq(other_updated_at.to_i)
    end
  end

  describe 'PATCH #update' do
    before do
      allow(controller).to receive(:allow_teacher_modify_prev_years)
    end
    let(:exam) do
      record = ConceptualExam.new(
        classroom: classroom,
        student: student,
        recorded_at: step.start_at,
        step_number: step.step_number,
        unity_id: unity.id
      )
      record.save!(validate: false)
      record
    end
    let!(:teacher_value) { create(:conceptual_exam_value, conceptual_exam: exam, discipline: teacher_discipline, value: 3) }
    let!(:other_value) { create(:conceptual_exam_value, conceptual_exam: exam, discipline: other_discipline, value: 8) }

    it 'updates only the current teacher disciplines and keeps other disciplines unchanged' do
      other_updated_at = other_value.updated_at

      patch :update, params: {
        locale: 'pt-BR',
        id: exam.id,
        conceptual_exam: {
          unity_id: unity.id,
          classroom_id: classroom.id,
          student_id: student.id,
          recorded_at: step.start_at,
          conceptual_exam_values_attributes: {
            '0' => {
              id: teacher_value.id,
              discipline_id: teacher_discipline.id,
              value: '7',
              _destroy: 'false'
            },
            '1' => {
              id: other_value.id,
              discipline_id: other_discipline.id,
              value: '1',
              _destroy: 'false'
            }
          }
        }
      }

      expect(teacher_value.reload.value.to_d).to eq(7.to_d)
      expect(other_value.reload.value.to_d).to eq(8.to_d)
      expect(other_value.updated_at.to_i).to eq(other_updated_at.to_i)
    end

    it 'does not destroy other teachers disciplines even when _destroy is sent' do
      patch :update, params: {
        locale: 'pt-BR',
        id: exam.id,
        conceptual_exam: {
          unity_id: unity.id,
          classroom_id: classroom.id,
          student_id: student.id,
          recorded_at: step.start_at,
          conceptual_exam_values_attributes: {
            '0' => {
              id: teacher_value.id,
              discipline_id: teacher_discipline.id,
              value: '7',
              _destroy: 'false'
            },
            '1' => {
              id: other_value.id,
              discipline_id: other_discipline.id,
              value: '8',
              _destroy: 'true'
            }
          }
        }
      }

      expect(ConceptualExamValue.exists?(other_value.id)).to eq(true)
      expect(other_value.reload.value.to_d).to eq(8.to_d)
    end
  end

  describe 'DELETE #destroy' do
    before do
      allow(controller).to receive(:allow_teacher_modify_prev_years)
    end
    it 'removes only the current teacher disciplines and keeps the exam when other teachers have values' do
      exam = ConceptualExam.new(
        classroom: classroom,
        student: student,
        recorded_at: step.start_at,
        step_number: step.step_number,
        unity_id: unity.id
      )
      exam.save!(validate: false)
      teacher_value = create(:conceptual_exam_value, conceptual_exam: exam, discipline: teacher_discipline, value: 3)
      other_value = create(:conceptual_exam_value, conceptual_exam: exam, discipline: other_discipline, value: 8)

      delete :destroy, params: { locale: 'pt-BR', id: exam.id }

      expect(ConceptualExam.exists?(exam.id)).to eq(true)
      expect(ConceptualExamValue.exists?(teacher_value.id)).to eq(false)
      expect(ConceptualExamValue.exists?(other_value.id)).to eq(true)
      expect(other_value.reload.value.to_d).to eq(8.to_d)
    end
  end
end
