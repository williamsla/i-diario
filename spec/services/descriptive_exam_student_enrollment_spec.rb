# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DescriptiveExamStudentEnrollment, type: :service do
  def enrollment(id:, joined_at:, left_at:)
    OpenStruct.new(id: id, joined_at: joined_at, left_at: left_at)
  end

  let(:period_start) { Date.new(2026, 8, 1) }
  let(:period_end) { Date.new(2026, 12, 18) }

  describe '.choose' do
    it 'usa a volta para a mesma turma e não a saída do remanejamento anterior' do
      left_class = enrollment(id: 1, joined_at: '2026-02-09', left_at: '2026-07-08')
      returned = enrollment(id: 3, joined_at: '2026-07-10', left_at: '')

      chosen = described_class.choose(
        [left_class, returned],
        period_start: period_start,
        period_end: period_end
      )

      expect(chosen).to eq(returned)
      expect(described_class.blocked?(chosen, period_start: period_start)).to eq(false)
    end

    it 'mantém bloqueado quem saiu antes do período e não voltou' do
      left_class = enrollment(id: 1, joined_at: '2026-02-09', left_at: '2026-07-08')

      chosen = described_class.choose(
        [left_class],
        period_start: period_start,
        period_end: period_end
      )

      expect(chosen).to eq(left_class)
      expect(described_class.blocked?(chosen, period_start: period_start)).to eq(true)
    end

    it 'não bloqueia quem saiu durante o período' do
      left_during = enrollment(id: 1, joined_at: '2026-02-09', left_at: '2026-09-01')

      chosen = described_class.choose(
        [left_during],
        period_start: period_start,
        period_end: period_end
      )

      expect(described_class.blocked?(chosen, period_start: period_start)).to eq(false)
    end

    it 'ignora enturmação de mesmo dia e fica com a vigente' do
      same_day = enrollment(id: 1, joined_at: '2026-07-08', left_at: '2026-07-08')
      returned = enrollment(id: 2, joined_at: '2026-07-10', left_at: nil)

      chosen = described_class.choose(
        [same_day, returned],
        period_start: period_start,
        period_end: period_end
      )

      expect(chosen).to eq(returned)
    end
  end
end
