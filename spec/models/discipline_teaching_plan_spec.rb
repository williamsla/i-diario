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

    def create_copied_plan_for(teacher)
      teaching_plan = create(
        :teaching_plan,
        teacher: teacher,
        unity: unity,
        grade: grade,
        school_term_type: school_term_type,
        school_term_type_step: school_term_type_step,
        year: year
      )
      teaching_plan.audits.where(action: 'create').update_all(user_id: nil, user_type: nil)
      create(
        :discipline_teaching_plan,
        teaching_plan: teaching_plan,
        discipline: discipline,
        thematic_unit: copied_thematic_unit
      )
    end

    let!(:my_plan) { create_plan_for(current_teacher, as_user: teacher_user) }
    let!(:other_plan) { create_plan_for(other_teacher, as_user: teacher_user) }

    let!(:unificado_plan) do
      create(
        :discipline_teaching_plan,
        discipline: discipline,
        thematic_unit: 'Outra unidade',
        teaching_plan: create(
          :teaching_plan,
          teacher: nil,
          unity: unity,
          grade: grade,
          school_term_type: school_term_type,
          school_term_type_step: school_term_type_step,
          year: year
        )
      )
    end

    let!(:admin_created_plan) do
      create_plan_for(other_teacher, as_user: admin, thematic_unit: 'Unidade admin')
    end

    let!(:copied_plan_a) { create_copied_plan_for(other_teacher) }
    let!(:copied_plan_b) { create_copied_plan_for(third_teacher) }

    it 'includes own plans and unificados for MY_PLANS' do
      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)

      expect(result).to include(my_plan, unificado_plan, admin_created_plan)
      expect(result).not_to include(other_plan)
    end

    it 'dedupes copied unificado plans with the same key for MY_PLANS' do
      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)
      copied_in_result = result.select { |plan| [copied_plan_a.id, copied_plan_b.id].include?(plan.id) }

      expect(copied_in_result.size).to eq(1)
      expect(copied_in_result.first.id).to eq([copied_plan_a.id, copied_plan_b.id].min)
    end

    it 'excludes own plans and unificados for OTHERS' do
      result = described_class.by_author(PlansAuthors::OTHERS, current_teacher)

      expect(result).to include(other_plan)
      expect(result).not_to include(
        my_plan, unificado_plan, admin_created_plan, copied_plan_a, copied_plan_b
      )
    end

    it 'includes all plans for ALL without deduping' do
      result = described_class.by_author(PlansAuthors::ALL, current_teacher)

      expect(result).to include(
        my_plan, other_plan, unificado_plan, admin_created_plan, copied_plan_a, copied_plan_b
      )
    end

    it 'prefers teacher_id nil when deduping unificados' do
      nil_teacher_copy = create(
        :discipline_teaching_plan,
        discipline: discipline,
        thematic_unit: copied_thematic_unit,
        teaching_plan: create(
          :teaching_plan,
          teacher: nil,
          unity: unity,
          grade: grade,
          school_term_type: school_term_type,
          school_term_type_step: school_term_type_step,
          year: year
        )
      )

      result = described_class.by_author(PlansAuthors::MY_PLANS, current_teacher)
      group = result.select { |plan| plan.thematic_unit == copied_thematic_unit }

      expect(group.size).to eq(1)
      expect(group.first).to eq(nil_teacher_copy)
      expect(group.first.teaching_plan[:teacher_id]).to be_nil
    end
  end
end
