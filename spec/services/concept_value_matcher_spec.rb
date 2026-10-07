require 'rails_helper'

RSpec.describe ConceptValueMatcher, type: :service do
  def concept(value, label)
    double(value: BigDecimal(value), label: label, to_s: "#{label} (#{value})")
  end

  let(:insufficient) { concept('5', 'NS') }
  let(:sufficient) { concept('7.0', 'S') }
  let(:full) { concept('10.00', 'PS') }
  let(:rounding_table) { double(rounding_table_values: [full, insufficient, sufficient], blank?: false) }

  describe '.canonical' do
    it 'unifica escalas e notação científica do mesmo número' do
      expect(described_class.canonical(BigDecimal('10.0'))).to eq('10')
      expect(described_class.canonical(BigDecimal('10.00'))).to eq('10')
      expect(described_class.canonical('0.1e2')).to eq('10')
      expect(described_class.canonical(BigDecimal('7.50'))).to eq('7.5')
    end
  end

  describe '.find' do
    it 'encontra o conceito mesmo quando a escala do decimal gravado é diferente' do
      expect(described_class.find(rounding_table, BigDecimal('10.0'))).to eq(full)
      expect(described_class.find(rounding_table, '0.1e2')).to eq(full)
      expect(described_class.find(rounding_table, BigDecimal('7.00'))).to eq(sufficient)
    end

    it 'usa a faixa do valor máximo, como a ficha individual do i-Educar' do
      expect(described_class.find(rounding_table, BigDecimal('8.5'))).to eq(full)
      expect(described_class.find(rounding_table, BigDecimal('6'))).to eq(sufficient)
      expect(described_class.find(rounding_table, BigDecimal('5'))).to eq(insufficient)
    end
  end

  describe '.display' do
    it 'mostra a sigla em vez do número' do
      expect(described_class.display(rounding_table, BigDecimal('10.0'))).to eq('PS')
      expect(described_class.display(rounding_table, BigDecimal('8.5'))).to eq('PS')
    end
  end

  describe '.option_id' do
    it 'devolve o id canônico da opção correspondente' do
      expect(described_class.option_id(rounding_table, BigDecimal('10.0'))).to eq('10')
      expect(described_class.option_id(rounding_table, BigDecimal('8.5'))).to eq('10')
    end
  end
end
