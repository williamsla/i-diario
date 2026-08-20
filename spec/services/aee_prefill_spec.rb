require 'rails_helper'

RSpec.describe AeePrefill do
  describe '.paee_from_case_study' do
    it 'returns characteristics and strategies from the case study' do
      case_study = create(:aee_case_study)

      result = described_class.paee_from_case_study(
        student: case_study.student,
        classroom: case_study.classroom,
        year: case_study.year
      )

      expect(result[:methodology]).to eq(case_study.accessibility_strategies)
      expect(result[:student_characteristics]).to include(case_study.identification)
      expect(result[:student_characteristics]).to include(case_study.potentialities_and_support)
    end

    it 'returns an empty hash when there is no case study' do
      student = create(:student)
      classroom = create(:classroom)

      expect(
        described_class.paee_from_case_study(student: student, classroom: classroom, year: Date.current.year)
      ).to eq({})
    end
  end

  describe '.content_record_from_pei' do
    it 'returns goals and strategies from the PEI' do
      pei = create(:aee_individual_plan)

      result = described_class.content_record_from_pei(
        student: pei.student,
        classroom: pei.classroom,
        year: pei.year
      )

      expect(result[:goals]).to eq(pei.goals)
      expect(result[:strategies]).to eq(pei.strategies)
      expect(result[:contents]).to eq([pei.strategies])
      expect(result[:objectives]).to eq([pei.goals])
    end
  end

  describe '.strip_html' do
    it 'removes html tags from rich text' do
      expect(described_class.strip_html('<p>Estratégia PAEE</p>')).to eq('Estratégia PAEE')
    end
  end
end
