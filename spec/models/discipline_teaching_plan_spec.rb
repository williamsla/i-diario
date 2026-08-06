require 'rails_helper'

RSpec.describe DisciplineTeachingPlan, type: :model do
  subject { build(:discipline_teaching_plan, :with_teacher_discipline_classroom) }

  before do
    allow_any_instance_of(TeachingPlan).to receive(:yearly?).and_return(true)
  end

  describe 'associations' do
    it { expect(subject).to belong_to(:teaching_plan).dependent(:destroy) }
    it { expect(subject).to belong_to(:discipline) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:teaching_plan) }
    it { expect(subject).to validate_presence_of(:discipline) }
  end

  describe '.by_author' do
    let(:current_teacher) { create(:teacher) }
    let(:other_teacher) { create(:teacher) }

    let!(:my_plan) do
      create(
        :discipline_teaching_plan,
        teaching_plan: create(:teaching_plan, teacher: current_teacher)
      )
    end

    let!(:other_plan) do
      create(
        :discipline_teaching_plan,
        teaching_plan: create(:teaching_plan, teacher: other_teacher)
      )
    end

    let!(:unificado_plan) do
      create(
        :discipline_teaching_plan,
        teaching_plan: create(:teaching_plan, teacher: nil)
      )
    end

    it 'includes own plans and unificados for MY_PLANS' do
      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)

      expect(result).to include(my_plan, unificado_plan)
      expect(result).not_to include(other_plan)
    end

    it 'excludes own plans and unificados for OTHERS' do
      result = described_class.by_author(PlansAuthors::OTHERS, current_teacher)

      expect(result).to include(other_plan)
      expect(result).not_to include(my_plan, unificado_plan)
    end

    it 'includes all plans for ALL' do
      result = described_class.by_author(PlansAuthors::ALL, current_teacher)

      expect(result).to include(my_plan, other_plan, unificado_plan)
    end
  end
end
