require 'rails_helper'

RSpec.describe TeachingPlan, type: :model do
  let!(:school_term_type) { create(:school_term_type) }

  let!(:school_term_type_step) { create(:school_term_type_step, school_term_type: school_term_type) }
  subject { build(
    :teaching_plan,
    school_term_type: school_term_type,
    school_term_type_step: school_term_type_step)
  }

  describe 'associations' do
    it { expect(subject).to belong_to(:unity) }
    it { expect(subject).to belong_to(:grade) }
  end

  describe '#unificado? / #semed?' do
    it 'returns true when persisted teacher_id is nil' do
      teaching_plan = create(:teaching_plan, teacher: nil)
      teaching_plan.reload

      expect(teaching_plan[:teacher_id]).to be_nil
      expect(teaching_plan.unificado?).to eq(true)
      expect(teaching_plan.semed?).to eq(true)
    end

    it 'returns false when teacher_id is present and creator is a teacher' do
      teacher = create(:teacher)
      teacher_user = create(:user, :with_user_role_teacher)
      teaching_plan = nil

      Audited.audit_class.as_user(teacher_user) do
        teaching_plan = create(:teaching_plan, teacher: teacher)
      end

      teaching_plan.reload
      expect(teaching_plan[:teacher_id]).to eq(teacher.id)
      expect(teaching_plan.unificado?).to eq(false)
    end

    it 'returns true when creator is administrator even with teacher_id present' do
      admin = create(:user, :with_user_role_administrator)
      teacher = create(:teacher)
      teaching_plan = nil

      Audited.audit_class.as_user(admin) do
        teaching_plan = create(:teaching_plan, teacher: teacher)
      end

      teaching_plan.reload
      expect(teaching_plan[:teacher_id]).to eq(teacher.id)
      expect(teaching_plan.created_by_administrator?).to eq(true)
      expect(teaching_plan.unificado?).to eq(true)
    end

    it 'returns true when creation audit has no user (typical copy)' do
      teacher = create(:teacher)
      teaching_plan = create(:teaching_plan, teacher: teacher)
      teaching_plan.audits.where(action: 'create').update_all(user_id: nil, user_type: nil)
      teaching_plan.reload

      expect(teaching_plan[:teacher_id]).to eq(teacher.id)
      expect(teaching_plan.created_without_user?).to eq(true)
      expect(teaching_plan.unificado?).to eq(true)
    end
  end

  describe 'validations' do
    it {
      TeachingPlan.any_instance.stub(:yearly?).and_return(true)
      expect(subject).to validate_presence_of(:year)
    }
    it {
      TeachingPlan.any_instance.stub(:yearly?).and_return(true)
      expect(subject).to validate_presence_of(:unity)
    }
    it {
      TeachingPlan.any_instance.stub(:yearly?).and_return(true)
      expect(subject).to validate_presence_of(:grade)
    }

    context 'when school term type is yearly' do
      subject { build(:teaching_plan, school_term_type: nil, school_term_type_step: nil) }

      it { expect(subject.school_term_type).to_not be_present  }
      it { expect(subject.school_term_type_step).to_not be_present  }
    end

    context 'when contents has no records assigneds' do
      it 'should validate if at leat one record is assigned' do
        TeachingPlan.any_instance.stub(:yearly?).and_return(true)

        subject = build(
          :teaching_plan,
          :without_contents,
          school_term_type: school_term_type,
          school_term_type_step: school_term_type_step
        )

        expect(subject).to_not be_valid
        expect(subject.errors.messages[:contents]).to include('Deve possuir pelo menos um conteúdo')
      end
    end
  end
end
