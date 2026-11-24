require 'rails_helper'

RSpec.describe AvaliationStepFillStatus, type: :service do
  def avaliation(id, test_setting_test_id: nil)
    row = Struct.new(:id, :test_setting_test_id)
    row.new(id, test_setting_test_id)
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

  describe 'Ruby 2.4.10' do
    it 'executa na versão fixada do projeto' do
      expect(RUBY_VERSION).to eq('2.4.10')
    end

    it 'compila o serviço e o controller' do
      [
        'app/services/avaliation_step_fill_status.rb',
        'app/controllers/avaliations_controller.rb'
      ].each do |relative|
        source = File.read(Rails.root.join(relative))
        RubyVM::InstructionSequence.compile(source)
      end
    end
  end

  describe '#by_step_id' do
    it 'não consulta nada quando a turma não tem etapas' do
      service = described_class.new(
        classroom: avaliation(1),
        discipline: avaliation(2),
        steps: []
      )

      expect(Avaliation).not_to receive(:by_classroom_id)
      expect(service.by_step_id).to eq({})
    end

    context 'com avaliações gravadas' do
      let(:classroom) { create(:classroom, :with_classroom_semester_steps) }
      let(:discipline) { create(:discipline) }
      let(:other_discipline) { create(:discipline) }
      let(:student) { create(:student) }
      let(:steps) { StepsFetcher.new(classroom).steps.order(:step_number).to_a }

      before do
        allow(TestSettingFetcher).to receive(:current).and_return(
          double('test_setting', sum_calculation_type?: false)
        )
      end

      def persist_avaliation(target_discipline, test_date)
        record = build(
          :avaliation,
          classroom: classroom,
          discipline: target_discipline,
          test_date: test_date,
          school_calendar: classroom.calendar.school_calendar
        )
        record.save(validate: false)
        record
      end

      def persist_note(target_avaliation, note)
        daily_note = DailyNote.new(avaliation_id: target_avaliation.id)
        daily_note.save(validate: false)
        DailyNoteStudent.new(
          daily_note_id: daily_note.id,
          student_id: student.id,
          note: note,
          active: true
        ).save(validate: false)
        daily_note
      end

      it 'mantém a etapa sem lançamento e ignora outra disciplina' do
        filled = persist_avaliation(discipline, Date.new(classroom.year, 3, 15))
        persist_note(filled, 8)
        other = persist_avaliation(other_discipline, Date.new(classroom.year, 3, 16))
        persist_note(other, nil)

        statuses = described_class.new(
          classroom: classroom,
          discipline: discipline,
          steps: steps
        ).by_step_id

        expect(statuses[steps.first.id].key).to eq(described_class::COMPLETE)
        expect(statuses[steps.first.id].complete_count).to eq(1)
        expect(statuses[steps.first.id].total_count).to eq(1)
        expect(statuses[steps.second.id].key).to eq(described_class::NOT_STARTED)
        expect(statuses[steps.second.id].total_count).to eq(0)
      end

      it 'marca a etapa como parcial quando falta nota de aluno enturmado' do
        grade_link = create(:classrooms_grade, classroom: classroom)
        enrollment = create(:student_enrollment, student: student)
        create(
          :student_enrollment_classroom,
          classrooms_grade: grade_link,
          student_enrollment: enrollment,
          joined_at: Date.new(classroom.year, 1, 1),
          left_at: ''
        )
        filled = persist_avaliation(discipline, Date.new(classroom.year, 3, 15))
        pending = persist_avaliation(discipline, Date.new(classroom.year, 3, 20))
        persist_note(filled, 8)
        persist_note(pending, nil)

        status = described_class.new(
          classroom: classroom,
          discipline: discipline,
          steps: steps
        ).by_step_id[steps.first.id]

        expect(status.key).to eq(described_class::PARTIAL)
        expect(status.complete_count).to eq(1)
        expect(status.total_count).to eq(2)
        expect(status.label_class).to eq('label-warning')
      end
    end
  end
end
