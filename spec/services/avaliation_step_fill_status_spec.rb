require 'rails_helper'

RSpec.describe AvaliationStepFillStatus, type: :service do
  AvaliationRow = Struct.new(:id, :test_setting_test_id)

  def avaliation(id, test_setting_test_id: nil)
    AvaliationRow.new(id, test_setting_test_id)
  end

  describe '.for_step' do
    it 'marca como não iniciada quando não há avaliação na etapa' do
      status = described_class.for_step(
        avaliations: [],
        instrument_test_ids: [],
        complete_ids: [],
        noted_ids: []
      )

      expect(status.key).to eq(described_class::NOT_STARTED)
      expect(status.complete_count).to eq(0)
      expect(status.total_count).to eq(0)
    end

    it 'marca como não iniciada quando os instrumentos do somatório ainda não têm nota' do
      status = described_class.for_step(
        avaliations: [],
        instrument_test_ids: [10, 20, 30],
        complete_ids: [],
        noted_ids: []
      )

      expect(status.key).to eq(described_class::NOT_STARTED)
      expect(status.complete_count).to eq(0)
      expect(status.total_count).to eq(3)
    end

    it 'marca como não iniciada quando a avaliação existe, mas nenhuma nota foi lançada' do
      status = described_class.for_step(
        avaliations: [avaliation(1), avaliation(2)],
        instrument_test_ids: [],
        complete_ids: [],
        noted_ids: []
      )

      expect(status.key).to eq(described_class::NOT_STARTED)
      expect(status.total_count).to eq(2)
    end

    it 'marca como parcial quando só parte das avaliações está completa' do
      status = described_class.for_step(
        avaliations: [avaliation(1), avaliation(2)],
        instrument_test_ids: [],
        complete_ids: [1],
        noted_ids: [1, 2]
      )

      expect(status.key).to eq(described_class::PARTIAL)
      expect(status.complete_count).to eq(1)
      expect(status.total_count).to eq(2)
    end

    it 'marca como parcial no somatório quando ainda falta instrumento' do
      status = described_class.for_step(
        avaliations: [avaliation(1, test_setting_test_id: 10)],
        instrument_test_ids: [10, 20],
        complete_ids: [1],
        noted_ids: [1]
      )

      expect(status.key).to eq(described_class::PARTIAL)
      expect(status.complete_count).to eq(1)
      expect(status.total_count).to eq(2)
    end

    it 'marca como todas preenchidas quando cada avaliação da etapa está completa' do
      status = described_class.for_step(
        avaliations: [avaliation(1), avaliation(2)],
        instrument_test_ids: [],
        complete_ids: [1, 2],
        noted_ids: [1, 2]
      )

      expect(status.key).to eq(described_class::COMPLETE)
      expect(status.complete_count).to eq(2)
      expect(status.total_count).to eq(2)
      expect(status.label_class).to eq('label-success')
    end

    it 'considera o instrumento completo quando alguma das cópias está completa' do
      status = described_class.for_step(
        avaliations: [
          avaliation(1, test_setting_test_id: 10),
          avaliation(2, test_setting_test_id: 10)
        ],
        instrument_test_ids: [10],
        complete_ids: [2],
        noted_ids: [2]
      )

      expect(status.key).to eq(described_class::COMPLETE)
      expect(status.complete_count).to eq(1)
      expect(status.total_count).to eq(1)
    end

    it 'trata avaliação completa sem nota numérica, como isenção, como iniciada' do
      status = described_class.for_step(
        avaliations: [avaliation(1)],
        instrument_test_ids: [],
        complete_ids: [1],
        noted_ids: []
      )

      expect(status.key).to eq(described_class::COMPLETE)
    end
  end

  describe '#by_step_id' do
    it 'devolve o status de cada etapa' do
      step = instance_double('SchoolCalendarStep', id: 7)
      service = described_class.new(
        classroom: instance_double('Classroom', id: 1),
        discipline: instance_double('Discipline', id: 2),
        steps: [step]
      )
      allow(service).to receive(:avaliations_in).with(step).and_return([avaliation(4)])
      allow(service).to receive(:instrument_test_ids_for).with(step).and_return([])
      allow(service).to receive(:complete_avaliation_ids).and_return(Set.new)
      allow(service).to receive(:avaliation_ids_with_note).and_return(Set[4])

      status = service.by_step_id[7]

      expect(status.key).to eq(described_class::PARTIAL)
      expect(status.complete_count).to eq(0)
      expect(status.total_count).to eq(1)
    end
  end
end
