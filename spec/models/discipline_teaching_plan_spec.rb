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
    let(:third_teacher) { create(:teacher) }
    let(:admin) { create(:user, :with_user_role_administrator) }
    let(:teacher_user) { create(:user, :with_user_role_teacher) }
    let(:unity) { create(:unity) }
    let(:grade) { create(:grade) }
    let(:discipline) { create(:discipline) }
    let(:school_term_type) { create(:school_term_type) }
    let(:school_term_type_step) { create(:school_term_type_step, school_term_type: school_term_type) }
    let(:year) { Date.current.year }
    let(:thematic_unit) { 'Artes Visuais' }
    let(:copied_thematic_unit) { 'Cópia institucional Arte' }

    def create_plan_for(teacher, as_user:, thematic_unit: self.thematic_unit, **teaching_plan_attrs)
      teaching_plan = nil
      Audited.audit_class.as_user(as_user) do
        teaching_plan = create(
          :teaching_plan,
          {
            teacher: teacher,
            unity: unity,
            grade: grade,
            school_term_type: school_term_type,
            school_term_type_step: school_term_type_step,
            year: year
          }.merge(teaching_plan_attrs)
        )
      end
      create(
        :discipline_teaching_plan,
        teaching_plan: teaching_plan,
        discipline: discipline,
        thematic_unit: thematic_unit
      )
    end

    let!(:my_plan) { create_plan_for(current_teacher, as_user: teacher_user) }
    let!(:other_plan) { create_plan_for(other_teacher, as_user: teacher_user) }

    let!(:nil_teacher_plan) do
      create_plan_for(nil, as_user: teacher_user, thematic_unit: 'Sem professor')
    end

    let!(:admin_created_plan) do
      create_plan_for(other_teacher, as_user: admin, thematic_unit: 'Unidade admin')
    end

    let!(:admin_copied_plan_a) do
      create_plan_for(other_teacher, as_user: admin, thematic_unit: copied_thematic_unit)
    end

    let!(:admin_copied_plan_b) do
      create_plan_for(third_teacher, as_user: admin, thematic_unit: copied_thematic_unit)
    end

    it 'includes own plans and unificados for MY_PLANS' do
      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)

      expect(result).to include(my_plan, admin_created_plan, nil_teacher_plan)
      expect(result).not_to include(other_plan)
    end

    it 'dedupes admin-created unificado plans with the same key for MY_PLANS' do
      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)
      copied_in_result = result.select { |plan| [admin_copied_plan_a.id, admin_copied_plan_b.id].include?(plan.id) }

      expect(copied_in_result.size).to eq(1)
      expect(copied_in_result.first.id).to eq([admin_copied_plan_a.id, admin_copied_plan_b.id].min)
    end

    it 'excludes own plans and unificados for OTHERS' do
      result = described_class.by_author(PlansAuthors::OTHERS, current_teacher)

      expect(result).to include(other_plan)
      expect(result).not_to include(
        my_plan, nil_teacher_plan, admin_created_plan, admin_copied_plan_a, admin_copied_plan_b
      )
    end

    it 'does not treat teacher plans as unificado when the creator also has administrator role' do
      dual_role_user = create(:user, :with_user_role_teacher)
      create(:user_role, :administrator, user: dual_role_user)
      dual_role_user.reload
      teacher_role = dual_role_user.user_roles.detect { |user_role|
        user_role.role.access_level == AccessLevel::TEACHER
      }
      dual_role_user.update!(current_user_role: teacher_role)

      teacher_plan = create_plan_for(current_teacher, as_user: dual_role_user)

      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)

      expect(dual_role_user.has_administrator_access_level?).to eq(true)
      expect(dual_role_user.administrator?).to eq(false)
      expect(teacher_plan.teaching_plan.unificado?).to eq(false)
      expect(result).to include(teacher_plan)
    end

    it 'includes all plans for ALL without deduping' do
      result = described_class.by_author(PlansAuthors::ALL, current_teacher)

      expect(result).to include(
        my_plan, other_plan, nil_teacher_plan, admin_created_plan, admin_copied_plan_a, admin_copied_plan_b
      )
    end

    it 'prefers teacher_id nil when deduping unificados' do
      nil_teacher_admin_copy = create_plan_for(
        nil,
        as_user: admin,
        thematic_unit: copied_thematic_unit
      )

      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)
      group = result.select { |plan| plan.thematic_unit == copied_thematic_unit }

      expect(group.size).to eq(1)
      expect(group.first).to eq(nil_teacher_admin_copy)
      expect(group.first.teaching_plan[:teacher_id]).to be_nil
    end
  end
end
