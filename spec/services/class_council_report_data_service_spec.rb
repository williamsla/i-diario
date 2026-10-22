require 'rails_helper'

RSpec.describe ClassCouncilReportDataService, type: :service do
  let(:service) { described_class.allocate }
  let(:classroom) { double(:classroom) }
  let(:student) { double(:student, id: 11) }
  let(:discipline) { double(:discipline, id: 22) }
  let(:step) { double(:step, step_number: 2) }

  before do
    service.instance_variable_set(:@classroom, classroom)
  end

  describe '#calculate_score' do
    it 'uses the numerical evaluations average for a numeric discipline' do
      allow(service).to receive(:student_has_gradable_score_type?).with(student).and_return(true)
      allow(service).to receive(:student_uses_conceptual_evaluation?).with(student, discipline).and_return(false)

      calculator = instance_double(ClassCouncilAverageCalculator, calculate: 9.5)
      expect(ClassCouncilAverageCalculator).to receive(:new).with(
        student: student,
        classroom: classroom,
        discipline: discipline,
        step: step
      ).and_return(calculator)

      expect(service.send(:calculate_score, student, discipline, step)).to eq(9.5)
    end

    it 'returns another step average from the same calculator' do
      allow(service).to receive(:student_has_gradable_score_type?).with(student).and_return(true)
      allow(service).to receive(:student_uses_conceptual_evaluation?).with(student, discipline).and_return(false)

      calculator = instance_double(ClassCouncilAverageCalculator, calculate: 10.0)
      allow(ClassCouncilAverageCalculator).to receive(:new).and_return(calculator)

      expect(service.send(:calculate_score, student, discipline, step)).to eq(10.0)
    end

    it 'keeps the concept of a conceptual discipline' do
      allow(service).to receive(:student_has_gradable_score_type?).with(student).and_return(true)
      allow(service).to receive(:student_uses_conceptual_evaluation?).with(student, discipline).and_return(true)
      allow(service).to receive(:conceptual_score).with(student, discipline, step).and_return('B')
      expect(ClassCouncilAverageCalculator).not_to receive(:new)

      expect(service.send(:calculate_score, student, discipline, step)).to eq('B')
    end

    it 'returns nil when the exam rule has no numeric or concept score' do
      allow(service).to receive(:student_has_gradable_score_type?).with(student).and_return(false)
      expect(ClassCouncilAverageCalculator).not_to receive(:new)

      expect(service.send(:calculate_score, student, discipline, step)).to be_nil
    end
  end

  describe '#step_payload' do
    before do
      service.instance_variable_set(:@disciplines, [discipline])
      service.instance_variable_set(:@frequency_by_discipline, false)
      service.instance_variable_set(:@minimum_scores_by_step, { 2 => 7 })
    end

    it 'exposes the cached step average' do
      service.instance_variable_set(:@scores_cache, { [11, 22, 2] => 9.5 })

      payload = service.send(:step_payload, student, step)

      expect(payload[:number]).to eq(2)
      expect(payload[:disciplines].first).to include(
        discipline_id: 22,
        score: 9.5,
        absences: 0,
        below_minimum: false
      )
    end

    it 'marks a numeric score below the promotion average' do
      service.instance_variable_set(:@scores_cache, { [11, 22, 2] => 5.0 })

      payload = service.send(:step_payload, student, step)

      expect(payload[:disciplines].first[:below_minimum]).to eq(true)
    end

    it 'does not mark a concept as below the minimum' do
      service.instance_variable_set(:@scores_cache, { [11, 22, 2] => 'B' })

      payload = service.send(:step_payload, student, step)

      expect(payload[:disciplines].first[:below_minimum]).to eq(false)
    end
  end
end
