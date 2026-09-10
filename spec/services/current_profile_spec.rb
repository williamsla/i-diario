require 'rails_helper'

RSpec.describe CurrentProfile do
  describe '#initialize' do
    let(:user) do
      instance_double(
        User,
        current_school_year: 2026,
        current_user_role: nil,
        current_unity: nil,
        current_classroom: nil,
        current_teacher: nil,
        current_discipline: nil
      )
    end

    it 'accepts ActionController::Parameters without converting them via with_indifferent_access' do
      params = ActionController::Parameters.new(by_school_year: 2025)

      expect(params).not_to receive(:with_indifferent_access)

      profile = described_class.new(user, params)

      expect(profile.school_year).to eq(2025)
    end

    it 'keeps hash access indifferent for regular hashes' do
      profile = described_class.new(user, 'by_school_year' => 2024)

      expect(profile.school_year).to eq(2024)
    end
  end
end
