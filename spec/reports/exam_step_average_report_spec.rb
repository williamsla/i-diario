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

  describe 'série na turma multisseriada' do
    let(:discipline) { create(:discipline) }

    def classroom_with_steps
      create(:classroom, :with_classroom_semester_steps, year: Date.current.year)
    end

    def enroll_student(classrooms_grade, name)
      student = create(:student, name: name)
      enrollment = create(:student_enrollment, student: student)
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        student_enrollment: enrollment
      )
      enrollment
    end

    before do
      allow(GeneralConfiguration).to receive(:semestral_recovery?).and_return(false)
      allow_any_instance_of(StudentAverageCalculator).to receive(:calculate).and_return(7.0)
    end

    it 'mostra a série do aluno no canto do nome' do
      classroom = classroom_with_steps
      sexta = create(:grade, description: '6 Ano Multisseriada')
      setima = create(:grade, description: '7 Ano Multisseriada')
      sexta_grade = create(:classrooms_grade, classroom: classroom, grade: sexta)
      create(:classrooms_grade, classroom: classroom, grade: setima)
      enrollment = enroll_student(sexta_grade, 'Aluno Da Sexta')

      text = pdf_text(build_report(classroom, discipline, [enrollment]))

      expect(text).to include('Aluno Da Sexta')
      expect(text).to include('6 Ano Multisseriada')
      expect(text).not_to include('7 Ano Multisseriada')
    end

    it 'mostra a série também na folha com recuperação semestral' do
      allow(GeneralConfiguration).to receive(:semestral_recovery?).and_return(true)
      classroom = classroom_with_steps
      sexta = create(:grade, description: '6 Ano Multisseriada')
      setima = create(:grade, description: '7 Ano Multisseriada')
      sexta_grade = create(:classrooms_grade, classroom: classroom, grade: sexta)
      create(:classrooms_grade, classroom: classroom, grade: setima)
      enrollment = enroll_student(sexta_grade, 'Aluno Da Sexta')

      text = pdf_text(build_report(classroom, discipline, [enrollment]))

      expect(text).to include('Semestre')
      expect(text).to include('6 Ano Multisseriada')
    end

    it 'omite a série quando a turma tem uma série só' do
      classroom = classroom_with_steps
      grade = create(:grade, description: 'Serie Unica Oculta')
      classrooms_grade = create(:classrooms_grade, classroom: classroom, grade: grade)
      enrollment = enroll_student(classrooms_grade, 'Aluno Serie Unica')

      text = pdf_text(build_report(classroom, discipline, [enrollment]))

      expect(text).to include('Aluno Serie Unica')
      expect(text).not_to include('Serie Unica Oculta')
    end
  end

  describe 'situação da disciplina' do
    let(:discipline) { create(:discipline) }

    def classroom_with_steps
      create(:classroom, :with_classroom_semester_steps, year: Date.current.year)
    end

    def enroll(classroom, status)
      classrooms_grade = create(:classrooms_grade, classroom: classroom)
      student = create(:student, name: 'Aluno Da Disciplina')
      enrollment = create(:student_enrollment, student: student, status: status)
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        student_enrollment: enrollment
      )
      enrollment
    end

    before do
      allow(GeneralConfiguration).to receive(:semestral_recovery?).and_return(false)
    end

    it 'mostra aprovado pela média da disciplina quando a matrícula está reprovada' do
      allow_any_instance_of(StudentAverageCalculator).to receive(:calculate).and_return(8.0)
      classroom = classroom_with_steps
      enrollment = enroll(classroom, StudentEnrollmentStatus::REPPROVED)

      text = pdf_text(build_report(classroom, discipline, [enrollment]))

      expect(text).to include('Aprovado')
      expect(text).not_to include('Reprovado')
    end

    it 'mostra reprovado pela média da disciplina quando a matrícula está aprovada' do
      allow_any_instance_of(StudentAverageCalculator).to receive(:calculate).and_return(3.0)
      classroom = classroom_with_steps
      enrollment = enroll(classroom, StudentEnrollmentStatus::APPROVED)

      text = pdf_text(build_report(classroom, discipline, [enrollment]))

      expect(text).to include('Reprovado')
    end

    it 'mantém cursando enquanto a matrícula segue em andamento' do
      allow_any_instance_of(StudentAverageCalculator).to receive(:calculate).and_return(8.0)
      classroom = classroom_with_steps
      enrollment = enroll(classroom, StudentEnrollmentStatus::STUDYING)

      text = pdf_text(build_report(classroom, discipline, [enrollment]))

      expect(text).to include('Cursando')
      expect(text).not_to include('Aprovado')
    end
  end
end
