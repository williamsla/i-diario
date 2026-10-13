require 'rails_helper'

RSpec.describe ConceptualExamStudentEnrollments, type: :service do
  let(:year) { Date.current.year }
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, unity: unity, year: year) }
  let(:discipline) { create(:discipline) }
  let(:old_classroom) do
    create(
      :classroom,
      :with_classroom_four_bimester_steps,
      unity: unity,
      year: year,
      school_calendar: school_calendar
    )
  end
  let(:new_classroom) { create(:classroom, unity: unity, year: year) }
  let(:old_classrooms_grade) { create(:classrooms_grade, :score_type_concept, classroom: old_classroom) }
  let(:new_classrooms_grade) { create(:classrooms_grade, :score_type_concept, classroom: new_classroom) }
  let(:steps) { StepsFetcher.new(old_classroom).steps }
  let(:first_class_day) { steps.first.start_at.to_date }

  def enrollments_for(step)
    described_class.new(
      classroom: old_classroom,
      discipline: discipline,
      start_at: step.start_at,
      end_at: step.end_at
    ).student_enrollments
  end

  def create_enrollment_in(classrooms_grade, student_enrollment, joined_at:, left_at:, show_as_inactive: false)
    create(
      :student_enrollment_classroom,
      classrooms_grade: classrooms_grade,
      student_enrollment: student_enrollment,
      joined_at: joined_at,
      left_at: left_at,
      show_as_inactive_when_not_in_date: show_as_inactive
    )
  end

  describe '#student_enrollments' do
    context 'quando o aluno foi remanejado no primeiro dia de aula' do
      let(:student) { create(:student) }
      let(:student_enrollment) { create(:student_enrollment, student: student) }
      let(:staying_student) { create(:student) }
      let(:staying_enrollment) { create(:student_enrollment, student: staying_student) }

      before do
        create_enrollment_in(
          old_classrooms_grade,
          student_enrollment,
          joined_at: "#{year}-01-01",
          left_at: first_class_day.to_s,
          show_as_inactive: true
        )
        create_enrollment_in(
          new_classrooms_grade,
          student_enrollment,
          joined_at: first_class_day.to_s,
          left_at: ''
        )
        create_enrollment_in(
          old_classrooms_grade,
          staying_enrollment,
          joined_at: "#{year}-01-01",
          left_at: ''
        )
      end

      it 'não lista o aluno remanejado em nenhuma etapa da turma antiga' do
        steps.each do |step|
          student_ids = enrollments_for(step).map(&:student_id)

          expect(student_ids).not_to include(student.id)
          expect(student_ids).to include(staying_student.id)
        end
      end

      it 'não lista o aluno remanejado mesmo com mostrar inativos habilitado' do
        GeneralConfiguration.current.update!(show_inactive_enrollments: true)

        steps.each do |step|
          expect(enrollments_for(step).map(&:student_id)).not_to include(student.id)
        end
      end
    end

    context 'quando o aluno foi remanejado no primeiro dia e a turma antiga ficou sem data de saída' do
      let(:student) { create(:student) }
      let(:student_enrollment) { create(:student_enrollment, student: student) }

      before do
        create_enrollment_in(
          old_classrooms_grade,
          student_enrollment,
          joined_at: "#{year}-01-01",
          left_at: ''
        )
        create_enrollment_in(
          new_classrooms_grade,
          student_enrollment,
          joined_at: first_class_day.to_s,
          left_at: ''
        )
      end

      it 'não lista o aluno na turma antiga em nenhuma etapa' do
        steps.each do |step|
          expect(enrollments_for(step).map(&:student_id)).not_to include(student.id)
        end
      end
    end

    context 'quando o aluno foi remanejado no meio da primeira etapa' do
      let(:student) { create(:student) }
      let(:student_enrollment) { create(:student_enrollment, student: student) }
      let(:left_at) { steps.first.start_at.to_date + 20.days }

      before do
        create_enrollment_in(
          old_classrooms_grade,
          student_enrollment,
          joined_at: "#{year}-01-01",
          left_at: left_at.to_s
        )
        create_enrollment_in(
          new_classrooms_grade,
          student_enrollment,
          joined_at: left_at.to_s,
          left_at: ''
        )
      end

      it 'lista o aluno só na primeira etapa da turma antiga' do
        expect(enrollments_for(steps.first).map(&:student_id)).to include(student.id)

        steps.to_a.drop(1).each do |step|
          expect(enrollments_for(step).map(&:student_id)).not_to include(student.id)
        end
      end
    end
  end
end
