require 'rails_helper'

RSpec.describe DisciplineLessonPlanReportForm, type: :model do
  let(:classroom) { create(:classroom, :with_teacher_discipline_classroom, :with_classroom_semester_steps) }
  let(:teacher_discipline_classroom) { classroom.teacher_discipline_classrooms.first }
  let(:teacher) { teacher_discipline_classroom.teacher }
  let(:discipline) { teacher_discipline_classroom.discipline }
  let(:student) { create(:student, uses_differentiated_exam_rule: true) }
  let(:other_student) { create(:student, uses_differentiated_exam_rule: true) }

  let(:general_lesson_plan) do
    create(
      :lesson_plan,
      classroom: classroom,
      teacher_id: teacher.id
    )
  end

  let(:individual_lesson_plan) do
    create(
      :lesson_plan,
      classroom: classroom,
      teacher_id: teacher.id,
      student_id: student.id
    )
  end

  let!(:general_discipline_lesson_plan) do
    create(
      :discipline_lesson_plan,
      lesson_plan: general_lesson_plan,
      discipline: discipline,
      teacher_id: teacher.id
    )
  end

  let!(:individual_discipline_lesson_plan) do
    create(
      :discipline_lesson_plan,
      lesson_plan: individual_lesson_plan,
      discipline: discipline,
      teacher_id: teacher.id
    )
  end

  let(:form) do
    described_class.new(
      unity_id: classroom.unity_id,
      classroom_id: classroom.id,
      discipline_id: discipline.id,
      teacher_id: teacher.id,
      date_start: general_lesson_plan.start_at,
      date_end: general_lesson_plan.end_at,
      author: PlansAuthors::ALL
    )
  end

  describe '#discipline_lesson_plan' do
    it 'returns general and individual plans when no student is selected' do
      expect(form.discipline_lesson_plan).to contain_exactly(
        general_discipline_lesson_plan,
        individual_discipline_lesson_plan
      )
    end

    it 'returns only the selected student individual plans' do
      form.student_id = student.id

      expect(form.discipline_lesson_plan).to contain_exactly(individual_discipline_lesson_plan)
    end

    it 'does not return another student individual plans' do
      form.student_id = other_student.id

      expect(form.discipline_lesson_plan).to be_empty
    end
  end

  describe '#discipline_content_record' do
    let(:general_content_record) do
      create(
        :content_record,
        :with_contents,
        classroom: classroom,
        teacher: teacher
      )
    end

    let(:individual_content_record) do
      create(
        :content_record,
        :with_contents,
        classroom: classroom,
        teacher: teacher,
        student_id: student.id
      )
    end

    let!(:general_discipline_content_record) do
      create(
        :discipline_content_record,
        content_record: general_content_record,
        discipline: discipline,
        teacher_id: teacher.id
      )
    end

    let!(:individual_discipline_content_record) do
      create(
        :discipline_content_record,
        content_record: individual_content_record,
        discipline: discipline,
        teacher_id: teacher.id
      )
    end

    before do
      form.date_start = general_content_record.record_date
      form.date_end = general_content_record.record_date
    end

    it 'returns general and individual records when no student is selected' do
      expect(form.discipline_content_record).to contain_exactly(
        general_discipline_content_record,
        individual_discipline_content_record
      )
    end

    it 'returns only the selected student individual records' do
      form.student_id = student.id

      expect(form.discipline_content_record).to contain_exactly(individual_discipline_content_record)
    end
  end
end
