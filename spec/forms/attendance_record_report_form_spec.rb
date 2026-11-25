require 'rails_helper'

RSpec.describe AttendanceRecordReportForm, type: :model do
  Frequency = Struct.new(:class_number, :period)

  describe '#collapse_frequencies_for_date' do
    subject(:form) { described_class.new(period: period) }

    context 'quando a impressão pede todos os turnos' do
      subject(:form) { described_class.new(period: Periods::FULL, all_periods: true) }

      it 'mantém a aula de cada turno' do
        frequencies = [
          Frequency.new(1, Periods::MATUTINAL.to_i),
          Frequency.new(2, Periods::MATUTINAL.to_i),
          Frequency.new(1, Periods::VESPERTINE.to_i),
          Frequency.new(2, Periods::VESPERTINE.to_i)
        ]

        collapsed = form.collapse_frequencies_for_date(frequencies)

        expect(collapsed.map { |frequency| [frequency.class_number, frequency.period] }).to eq([
          [1, Periods::MATUTINAL.to_i],
          [2, Periods::MATUTINAL.to_i],
          [1, Periods::VESPERTINE.to_i],
          [2, Periods::VESPERTINE.to_i]
        ])
      end
    end

    context 'quando o diário consulta todos os turnos sem pedir a lista completa' do
      let(:period) { Periods::FULL }

      it 'mantém uma coluna por aula no mesmo dia' do
        frequencies = [
          Frequency.new(1, Periods::MATUTINAL.to_i),
          Frequency.new(2, Periods::MATUTINAL.to_i),
          Frequency.new(1, Periods::VESPERTINE.to_i),
          Frequency.new(2, Periods::VESPERTINE.to_i)
        ]

        collapsed = form.collapse_frequencies_for_date(frequencies)

        expect(collapsed.map(&:class_number)).to eq([1, 2])
      end

      it 'prefere o registro do turno integral quando a mesma aula existe nos dois' do
        frequencies = [
          Frequency.new(1, Periods::MATUTINAL.to_i),
          Frequency.new(1, Periods::FULL.to_i)
        ]

        collapsed = form.collapse_frequencies_for_date(frequencies)

        expect(collapsed.map(&:period)).to eq([Periods::FULL.to_i])
      end
    end

    context 'quando o relatório filtra um turno' do
      let(:period) { Periods::VESPERTINE }

      it 'mantém as aulas distintas desse turno' do
        frequencies = [
          Frequency.new(1, Periods::VESPERTINE.to_i),
          Frequency.new(2, Periods::VESPERTINE.to_i)
        ]

        collapsed = form.collapse_frequencies_for_date(frequencies)

        expect(collapsed.map(&:class_number)).to eq([1, 2])
      end

      it 'descarta a cópia da mesma aula em outro turno' do
        frequencies = [
          Frequency.new(1, Periods::MATUTINAL.to_i),
          Frequency.new(1, Periods::VESPERTINE.to_i)
        ]

        collapsed = form.collapse_frequencies_for_date(frequencies)

        expect(collapsed.map(&:period)).to eq([Periods::VESPERTINE.to_i])
      end
    end
  end
end
