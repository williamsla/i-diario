require 'rails_helper'

RSpec.describe ConceptualExamStepOverviewFetcher, type: :service do
  describe ConceptualExamStepOverviewFetcher::StepOverview do
    it 'calculates complete percentage' do
      overview = described_class.new(nil, 5, 3, 2, 10, false)

      expect(overview.complete_percentage).to eq(50)
    end

    it 'returns zero percentage when total is zero' do
      overview = described_class.new(nil, 0, 0, 0, 0, false)

      expect(overview.complete_percentage).to eq(0)
    end
  end

  describe '#status helpers via constants' do
    it 'defines pending status' do
      expect(ConceptualExamStepOverviewFetcher::PENDING).to eq('pending')
    end
  end

  describe '#student_rows_for_step' do
    let(:year) { Date.current.year }
    let(:unity) { create(:unity) }
    let(:school_calendar) { create(:school_calendar, unity: unity, year: year) }
    let(:discipline) { create(:discipline) }
    let(:classroom) do
      create(
        :classroom,
        :with_classroom_four_bimester_steps,
        unity: unity,
        year: year,
        school_calendar: school_calendar
      )
    end
    let(:new_classroom) { create(:classroom, unity: unity, year: year) }
    let(:classrooms_grade) { create(:classrooms_grade, :score_type_concept, classroom: classroom) }
    let(:new_classrooms_grade) { create(:classrooms_grade, :score_type_concept, classroom: new_classroom) }
    let(:steps) { StepsFetcher.new(classroom).steps }
    let(:student) { create(:student) }
    let(:student_enrollment) { create(:student_enrollment, student: student) }
    let(:fetcher) do
      described_class.new(classroom: classroom, teacher_id: 1, discipline: discipline)
    end

    it 'não inclui aluno remanejado no primeiro dia de aula em nenhuma etapa da turma antiga' do
      first_class_day = steps.first.start_at.to_date
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        student_enrollment: student_enrollment,
        joined_at: "#{year}-01-01",
        left_at: first_class_day.to_s,
        show_as_inactive_when_not_in_date: true
      )
      create(
        :student_enrollment_classroom,
        classrooms_grade: new_classrooms_grade,
        student_enrollment: student_enrollment,
        joined_at: first_class_day.to_s,
        left_at: ''
      )

      steps.each do |step|
        student_ids = fetcher.student_rows_for_step(step).map { |row| row.student.id }

        expect(student_ids).not_to include(student.id)
      end
    end
  end
end

