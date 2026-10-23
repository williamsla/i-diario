require 'rails_helper'

RSpec.describe PostedExamScoreRefresher, type: :service do
  describe '.enqueue' do
    it 'does not enqueue when no student had a score' do
      expect(RefreshPostedExamScoresWorker).not_to receive(:perform_async)

      described_class.enqueue('student_ids' => [])
    end

    it 'enqueues the refresh for the current entity' do
      entity = double(:entity, id: 7)
      snapshot = { 'student_ids' => [3] }
      allow(Entity).to receive(:current).and_return(entity)

      expect(RefreshPostedExamScoresWorker).to receive(:perform_async).with(7, snapshot)

      described_class.enqueue(snapshot)
    end
  end

  describe '#call' do
    let(:classroom) { double(:classroom, id: 10, api_code: 'turma') }
    let(:discipline) { double(:discipline, id: 20, api_code: 'disc') }
    let(:step) { double(:step, id: 30, to_number: 1) }
    let(:student) { double(:student, id: 3, api_code: 'aluno') }
    let(:configuration) { double(:configuration, url: 'https://ieducar.test', to_api: { url: 'https://ieducar.test' }) }
    let(:calculator) { instance_double(StudentAverageCalculator) }
    let(:snapshot) do
      { 'classroom_id' => 10, 'discipline_id' => 20, 'test_date' => '2026-03-01', 'student_ids' => [3] }
    end

    before do
      allow(Classroom).to receive(:find_by).with(id: 10).and_return(classroom)
      allow(Discipline).to receive(:find_by).with(id: 20).and_return(discipline)
      allow(StepsFetcher).to receive(:new).with(classroom).and_return(double(step_by_date: step))
      allow(IeducarApiConfiguration).to receive(:current).and_return(configuration)
      allow(Student).to receive(:find_by).with(id: 3).and_return(student)
      allow(StudentAverageCalculator).to receive(:new).with(student).and_return(calculator)
      relation = double(:relation)
      allow(IeducarApiExamPosting).to receive(:where).and_return(relation)
      allow(relation).to receive(:where).and_return(relation)
      allow(relation).to receive(:exists?).and_return(true)
    end

    it 'removes the remote score when the step no longer has a local average' do
      enrollment = double(:enrollment, api_code: 'matricula')
      api = instance_double(IeducarApi::DeleteExamScore)
      allow(calculator).to receive(:calculate)
        .with(classroom, discipline, step, ieducar_fallback: false)
        .and_return(nil)
      allow(StudentClassroomEnrollments).to receive(:for_student).with(3, 10).and_return([enrollment])
      expect(IeducarApi::DeleteExamScore).to receive(:new).with(configuration.to_api).and_return(api)
      expect(api).to receive(:send_delete).with(
        etapa: 1,
        matricula_id: 'matricula',
        componente_curricular_id: 'disc'
      )

      described_class.new(snapshot).call
    end

    it 'reposts the new average when the student still has scores in the step' do
      api = instance_double(IeducarApi::PostExams)
      allow(calculator).to receive(:calculate)
        .with(classroom, discipline, step, ieducar_fallback: false)
        .and_return(5.0)
      expect(IeducarApi::PostExams).to receive(:new).with(configuration.to_api).and_return(api)
      expect(api).to receive(:send_post).with(
        etapa: 1,
        resource: 'notas',
        notas: { 'turma' => { 'aluno' => { 'disc' => { 'nota' => 5.0 } } } }
      )

      described_class.new(snapshot).call
    end

    it 'does nothing when the step was never posted' do
      relation = double(:relation)
      allow(IeducarApiExamPosting).to receive(:where).and_return(relation)
      allow(relation).to receive(:where).and_return(relation)
      allow(relation).to receive(:exists?).and_return(false)
      expect(StudentAverageCalculator).not_to receive(:new)

      described_class.new(snapshot).call
    end
  end
end
