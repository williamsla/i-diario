require 'rails_helper'

RSpec.describe PlanAuthorFetcher do
  let(:current_teacher) { create(:teacher) }
  let(:other_teacher) { create(:teacher) }

  describe '#author' do
    subject { described_class.new(teaching_plan, current_teacher).author }

    context 'when the plan has teacher_id nil but was not created by administrator' do
      let(:teaching_plan) { create(:teaching_plan, teacher: nil) }

      it 'returns others' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.others'))
      end
    end

    context 'when the plan was created by an administrator' do
      let(:admin) { create(:user, :with_user_role_administrator) }
      let(:teaching_plan) do
        plan = nil
        Audited.audit_class.as_user(admin) do
          plan = create(:teaching_plan, teacher: other_teacher)
        end
        plan
      end

      it 'returns my_plans' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.my_plans'))
      end
    end

    context 'when the plan belongs to the current teacher' do
      let(:teaching_plan) { create(:teaching_plan, teacher: current_teacher) }

      it 'returns my_plans' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.my_plans'))
      end
    end

    context 'when the plan belongs to another teacher with a teacher creator' do
      let(:teacher_user) { create(:user, :with_user_role_teacher) }
      let(:teaching_plan) do
        plan = nil
        Audited.audit_class.as_user(teacher_user) do
          plan = create(:teaching_plan, teacher: other_teacher)
        end
        plan
      end

      it 'returns others' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.others'))
      end
    end

    context 'when creation audit has no user' do
      let(:teaching_plan) do
        plan = create(:teaching_plan, teacher: other_teacher)
        plan.audits.where(action: 'create').update_all(user_id: nil, user_type: nil)
        plan.reload
      end

      it 'returns others' do
        expect(subject).to eq(I18n.t('enumerations.plans_authors.others'))
      end
    end
  end
end
