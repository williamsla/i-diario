require 'rails_helper'

RSpec.describe ConceptualExamStepOverviewFetcher, type: :service do
  describe ConceptualExamStepOverviewFetcher::StepOverview do
    it 'calculates complete percentage' do
      overview = described_class.new(nil, 5, 3, 2, 10, false)

      expect(overview.complete_percentage).to eq(50)
    end

    it 'returns zero percentage when total is zero' do
      overview = described_class.new(nil, 0, 0, 0, 0, false)

      expect(overview.complete_percentage).to eq(0)
    end
  end

  describe '#status helpers via constants' do
    it 'defines pending status' do
      expect(ConceptualExamStepOverviewFetcher::PENDING).to eq('pending')
    end
  end
end
