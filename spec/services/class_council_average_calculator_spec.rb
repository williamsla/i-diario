require 'rails_helper'

RSpec.describe ClassCouncilAverageCalculator, type: :service do
  describe '.average_for' do
    let(:test_setting) do
      double(:test_setting).tap do |setting|
        allow(setting).to receive(:sum_calculation_type?).and_return(false)
        allow(setting).to receive(:arithmetic_and_sum_calculation_type?).and_return(false)
      end
    end

    it 'divides a sum of 38 by the configured weight of 4' do
      allow(test_setting).to receive(:sum_calculation_type?).and_return(true)
      allow(test_setting).to receive(:default_division_weight).and_return(4)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 38.0,
        scores_count: 4,
        weight_sum: nil
      )

      expect(result).to eq(9.5)
    end

    it 'divides two scores of 10 by a weight of 4' do
      allow(test_setting).to receive(:sum_calculation_type?).and_return(true)
      allow(test_setting).to receive(:default_division_weight).and_return(4)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 20.0,
        scores_count: 2,
        weight_sum: nil
      )

      expect(result).to eq(5.0)
    end

    it 'divides the same sum by a weight of 2' do
      allow(test_setting).to receive(:sum_calculation_type?).and_return(true)
      allow(test_setting).to receive(:default_division_weight).and_return(2)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 20.0,
        scores_count: 2,
        weight_sum: nil
      )

      expect(result).to eq(10.0)
    end

    it 'shows the sum when the division weight is 1' do
      allow(test_setting).to receive(:sum_calculation_type?).and_return(true)
      allow(test_setting).to receive(:default_division_weight).and_return(1)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 20.0,
        scores_count: 2,
        weight_sum: nil
      )

      expect(result).to eq(20.0)
    end

    it 'uses the number of scores for an arithmetic average' do
      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 20.0,
        scores_count: 2,
        weight_sum: 4
      )

      expect(result).to eq(10.0)
    end

    it 'normalizes a weighted sum to a 0..10 scale' do
      allow(test_setting).to receive(:arithmetic_and_sum_calculation_type?).and_return(true)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 18.0,
        scores_count: 2,
        weight_sum: 18
      )

      expect(result).to eq(10.0)
    end

    it 'returns nil when the weight sum is zero' do
      allow(test_setting).to receive(:arithmetic_and_sum_calculation_type?).and_return(true)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 18.0,
        scores_count: 2,
        weight_sum: 0
      )

      expect(result).to be_nil
    end

    it 'returns nil when the weight sum is blank' do
      allow(test_setting).to receive(:arithmetic_and_sum_calculation_type?).and_return(true)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 18.0,
        scores_count: 2,
        weight_sum: nil
      )

      expect(result).to be_nil
    end

    it 'divides a sum by a weight of 3' do
      allow(test_setting).to receive(:sum_calculation_type?).and_return(true)
      allow(test_setting).to receive(:default_division_weight).and_return(3)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 27.0,
        scores_count: 3,
        weight_sum: nil
      )

      expect(result).to eq(9.0)
    end

    it 'keeps the sum rule when the weighted rule is also enabled' do
      allow(test_setting).to receive(:sum_calculation_type?).and_return(true)
      allow(test_setting).to receive(:default_division_weight).and_return(4)

      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 20.0,
        scores_count: 2,
        weight_sum: 10
      )

      expect(result).to eq(5.0)
    end

    it 'returns zero when an arithmetic average has no scores' do
      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 0,
        scores_count: 0,
        weight_sum: nil
      )

      expect(result).to eq(0)
    end

    it 'averages three arithmetic scores' do
      result = described_class.average_for(
        test_setting: test_setting,
        score_sum: 29.0,
        scores_count: 3,
        weight_sum: nil
      )

      expect(result).to eq(29.0 / 3)
    end
  end

  describe '#calculate' do
    it 'returns the same average as the numerical evaluations report' do
      student = double(:student)
      classroom = double(:classroom)
      discipline = double(:discipline)
      step = double(:step)
      report_calculator = instance_double(StudentAverageCalculator)

      expect(StudentAverageCalculator).to receive(:new).with(student).and_return(report_calculator)
      expect(report_calculator).to receive(:calculate)
        .with(classroom, discipline, step, ieducar_fallback: false)
        .and_return(9.5)

      result = described_class.new(
        student: student,
        classroom: classroom,
        discipline: discipline,
        step: step
      ).calculate

      expect(result).to eq(9.5)
    end

    it 'keeps an empty step blank when the student already has a diary in the classroom' do
      student = double(:student, id: 1)
      classroom = double(:classroom, id: 2)
      discipline = double(:discipline)
      step = double(:step)
      report_calculator = instance_double(StudentAverageCalculator)
      calculator = described_class.new(
        student: student,
        classroom: classroom,
        discipline: discipline,
        step: step
      )

      allow(StudentAverageCalculator).to receive(:new).with(student).and_return(report_calculator)
      expect(report_calculator).to receive(:calculate)
        .with(classroom, discipline, step, ieducar_fallback: false)
        .and_return(nil)
      expect(report_calculator).not_to receive(:calculate).with(classroom, discipline, step)
      allow(calculator).to receive(:diary_in_classroom?).and_return(true)

      expect(calculator.calculate).to be_nil
    end

    it 'uses i-Educar only when the student never had a diary in the classroom' do
      student = double(:student, id: 1)
      classroom = double(:classroom, id: 2)
      discipline = double(:discipline)
      step = double(:step)
      report_calculator = instance_double(StudentAverageCalculator)
      calculator = described_class.new(
        student: student,
        classroom: classroom,
        discipline: discipline,
        step: step
      )

      allow(StudentAverageCalculator).to receive(:new).with(student).and_return(report_calculator)
      expect(report_calculator).to receive(:calculate)
        .with(classroom, discipline, step, ieducar_fallback: false)
        .and_return(nil)
      expect(report_calculator).to receive(:calculate).with(classroom, discipline, step).and_return(9.5)
      allow(calculator).to receive(:diary_in_classroom?).and_return(false)

      expect(calculator.calculate).to eq(9.5)
    end
  end
end
