require 'rails_helper'

RSpec.describe StudentNotesQuery, type: :query do
  let(:year) { Date.current.year }
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_trimester_steps, unity: unity, year: year) }
  let(:classroom) { create(:classroom, unity: unity, year: year) }
  let(:classrooms_grade) { create(:classrooms_grade, classroom: classroom) }
  let(:discipline) { create(:discipline) }
  let(:teacher) { create(:teacher) }
  let(:student) { create(:student) }
  let(:student_enrollment) { create(:student_enrollment, student: student) }
  let(:step) { school_calendar.steps.first }

  let(:avaliation) do
    create(
      :avaliation,
      :with_teacher_discipline_classroom,
      classroom: classroom,
      discipline: discipline,
      school_calendar: school_calendar,
      teacher: teacher,
      teacher_id: teacher.id,
      test_date: test_date
    )
  end
  let(:daily_note) { create(:daily_note, avaliation: avaliation) }
  let!(:daily_note_student) do
    create(
      :daily_note_student,
      daily_note: daily_note,
      student: student,
      note: 2,
      active: true
    )
  end

  subject do
    described_class.new(student, discipline, classroom, step.start_at, step.end_at)
  end

  describe '#daily_note_students' do
    context 'quando o aluno chegou no meio da etapa depois das avaliações' do
      let(:test_date) { step.start_at.to_date + 5.days }
      let!(:student_enrollment_classroom) do
        create(
          :student_enrollment_classroom,
          student_enrollment: student_enrollment,
          classrooms_grade: classrooms_grade,
          joined_at: (step.end_at.to_date - 10.days).to_s,
          left_at: ''
        )
      end

      it 'inclui a nota habilitada pelo professor' do
        expect(subject.daily_note_students).to include(daily_note_student)
      end
    end

    context 'quando o aluno chegou depois que a etapa já tinha acabado' do
      let(:test_date) { step.end_at.to_date }
      let!(:student_enrollment_classroom) do
        create(
          :student_enrollment_classroom,
          student_enrollment: student_enrollment,
          classrooms_grade: classrooms_grade,
          joined_at: (step.end_at.to_date + 5.days).to_s,
          left_at: ''
        )
      end

      it 'inclui a nota habilitada pelo professor' do
        expect(subject.daily_note_students).to include(daily_note_student)
      end
    end
  end
end
