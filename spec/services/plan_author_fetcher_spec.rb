require 'rails_helper'

RSpec.describe PlanAuthorFetcher do
  let(:current_teacher) { create(:teacher) }
  let(:other_teacher) { create(:teacher) }

  describe '#author' do
    subject { described_class.new(teaching_plan, current_teacher).author }

    context 'when the plan is unificado (teacher_id nil)' do
      let(:teaching_plan) { create(:teaching_plan, teacher: nil) }

      it 'returns my_plans (not others)' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.my_plans'))
      end
    end

    context 'when the plan belongs to the current teacher' do
      let(:teaching_plan) { create(:teaching_plan, teacher: current_teacher) }

      it 'returns my_plans' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.my_plans'))
      end
    end

    context 'when the plan belongs to another teacher' do
      let(:teaching_plan) { create(:teaching_plan, teacher: other_teacher) }

      it 'returns others' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.others'))
      end
    end
  end
end
