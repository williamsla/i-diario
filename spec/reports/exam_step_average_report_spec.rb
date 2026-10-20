require 'rails_helper'
require 'pdf/reader'

RSpec.describe ExamStepAverageReport, type: :report do
  def pdf_text(report)
    reader = PDF::Reader.new(StringIO.new(report.render))
    reader.pages.map(&:text).join("\n")
  end

  def build_report(classroom, discipline, enrollments)
    described_class.build(
      create(:entity_configuration),
      classroom.unity,
      create(:teacher),
      classroom.year,
      classroom,
      discipline,
      classroom.calendar.classroom_steps.to_a,
      enrollments
    )
  end

  describe 'recuperação semestral' do
    let(:discipline) { create(:discipline) }
    let(:classroom) do
      create(
        :classroom,
        :with_classroom_semester_steps,
        :score_type_numeric,
        :with_student_enrollment_classroom,
        year: Date.current.year
      )
    end
    let(:enrollments) { classroom.student_enrollment_classrooms.map(&:student_enrollment) }

    before do
      allow_any_instance_of(StudentAverageCalculator).to receive(:calculate) do |_calculator, _classroom, _discipline, step|
        step.step_number == 1 ? 3.0 : 2.0
      end
    end

    it 'mantém uma recuperação por etapa quando a configuração semestral está desligada' do
      allow(GeneralConfiguration).to receive(:semestral_recovery?).and_return(false)

      text = pdf_text(build_report(classroom, discipline, enrollments))

      expect(text).to include('Rec 1')
      expect(text).not_to include('Semestre')
    end

    it 'calcula a média do semestre com as duas etapas e uma única recuperação' do
      allow(GeneralConfiguration).to receive(:semestral_recovery?).and_return(true)
      fetcher = instance_double(SchoolTermRecoveryScoresFetcher)
      allow(SchoolTermRecoveryScoresFetcher).to receive(:new).and_return(fetcher)
      allow(fetcher).to receive(:score_for) do |_student_id, step|
        step&.step_number == 2 ? 6.0 : nil
      end

      text = pdf_text(build_report(classroom, discipline, enrollments))

      expect(text).to include('Semestre')
      expect(text).not_to include('Rec 1')
      expect(text).to include('3,0')
      expect(text).to include('2,0')
      expect(text).to include('2,5')
      expect(text).to include('6,0')
      expect(text).to include('4,2')
    end

    it 'faz a média da recuperação final com a média do semestre' do
      allow(GeneralConfiguration).to receive(:semestral_recovery?).and_return(true)
      student_id = enrollments.first.student_id
      fetcher = instance_double(SchoolTermRecoveryScoresFetcher)
      allow(SchoolTermRecoveryScoresFetcher).to receive(:new).and_return(fetcher)
      allow(fetcher).to receive(:score_for) do |_student_id, step|
        step&.step_number == 2 ? 6.0 : nil
      end
      allow_any_instance_of(described_class).to receive(:load_final_recovery_scores).and_return(student_id => 5.0)

      text = pdf_text(build_report(classroom, discipline, enrollments))

      expect(text).to include('4,2')
      expect(text).to include('5,0')
      expect(text).to include('4,6')
    end
  end
end
