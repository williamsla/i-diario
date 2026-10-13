require 'rails_helper'

RSpec.describe KnowledgeAreaTeachingPlan, type: :model do
  subject {
    build(
      :knowledge_area_teaching_plan,
      :with_teacher_discipline_classroom
    )
  }

  before do
    allow_any_instance_of(TeachingPlan).to receive(:yearly?).and_return(true)
  end

  describe 'associations' do
    it { expect(subject).to belong_to(:teaching_plan) }
    it { expect(subject).to have_many(:knowledge_area_teaching_plan_knowledge_areas).dependent(:destroy) }
    it { expect(subject).to have_many(:knowledge_areas).through(:knowledge_area_teaching_plan_knowledge_areas) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:teaching_plan) }
    it { expect(subject).to validate_presence_of(:knowledge_area_ids) }
  end

  describe '.unificado_exists_for_same_step?' do
    let(:grade) { create(:grade) }
    let(:school_term_type) { create(:school_term_type) }
    let(:school_term_type_step) { create(:school_term_type_step, school_term_type: school_term_type) }
    let(:knowledge_area) { create(:knowledge_area) }
    let(:other_knowledge_area) { create(:knowledge_area) }
    let(:candidate) do
      TeachingPlan.new(
        unity: create(:unity),
        grade: grade,
        year: Date.current.year,
        school_term_type: school_term_type,
        school_term_type_step: school_term_type_step
      )
    end

    def create_unificado_plan(knowledge_areas)
      teaching_plan = create(
        :teaching_plan,
        unificado: true,
        teacher: nil,
        grade: grade,
        year: candidate.year,
        school_term_type: school_term_type,
        school_term_type_step: school_term_type_step,
        unity: create(:unity)
      )
      plan = build(:knowledge_area_teaching_plan, teaching_plan: teaching_plan)
      plan.knowledge_area_ids = knowledge_areas.map(&:id)
      plan.save!
      plan
    end

    it 'detects a unificado plan with the same knowledge areas and step' do
      create_unificado_plan([knowledge_area, other_knowledge_area])

      expect(
        described_class.unificado_exists_for_same_step?(
          candidate,
          [other_knowledge_area.id, knowledge_area.id]
        )
      ).to eq(true)
    end

    it 'ignores a unificado plan with different knowledge areas' do
      create_unificado_plan([other_knowledge_area])

      expect(
        described_class.unificado_exists_for_same_step?(candidate, [knowledge_area.id])
      ).to eq(false)
    end
  end
end
