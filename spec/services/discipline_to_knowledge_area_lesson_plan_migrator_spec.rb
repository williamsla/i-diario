require 'rails_helper'

RSpec.describe DisciplineToKnowledgeAreaLessonPlanMigrator do
  let(:classroom) { create(:classroom, :with_classroom_semester_steps) }
  let(:teacher) { create(:teacher) }
  let(:knowledge_area) { create(:knowledge_area) }
  let(:discipline) { create(:discipline, knowledge_area: knowledge_area) }
  let(:content) { create(:content) }
  let(:objective) { create(:objective) }
  let(:lesson_plan) do
    create(
      :lesson_plan,
      :with_teacher_discipline_classroom,
      classroom: classroom,
      teacher: teacher,
      discipline: discipline,
      contents: [content],
      objectives: [objective]
    )
  end
  let(:discipline_lesson_plan) do
    create(
      :discipline_lesson_plan,
      lesson_plan: lesson_plan,
      discipline: discipline,
      teacher_id: teacher.id,
      thematic_unit: 'Unidade 1'
    )
  end

  describe '#call' do
    it 'simula a migração sem gravar quando dry_run é true' do
      result = described_class.new(
        discipline_lesson_plan_ids: [discipline_lesson_plan.id],
        dry_run: true
      ).call

      expect(result.created).to eq(1)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaLessonPlan.count).to eq(0)
      expect(DisciplineLessonPlan.exists?(discipline_lesson_plan.id)).to be(true)
    end

    it 'cria plano por área usando a área da disciplina e mantém o plano por disciplina' do
      result = described_class.new(
        discipline_lesson_plan_ids: [discipline_lesson_plan.id],
        dry_run: false
      ).call

      expect(result.created).to eq(1)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaLessonPlan.count).to eq(1)

      ka_lesson_plan = KnowledgeAreaLessonPlan.last
      expect(ka_lesson_plan.knowledge_areas).to eq([knowledge_area])
      expect(ka_lesson_plan.teacher_id).to eq(teacher.id)
      expect(ka_lesson_plan.experience_fields).to eq('Unidade 1')
      expect(ka_lesson_plan.lesson_plan.contents).to eq([content])
      expect(ka_lesson_plan.lesson_plan.objectives).to eq([objective])
      expect(ka_lesson_plan.lesson_plan.start_at).to eq(lesson_plan.start_at)
      expect(ka_lesson_plan.lesson_plan.end_at).to eq(lesson_plan.end_at)
      expect(ka_lesson_plan.lesson_plan.teacher_id).to eq(teacher.id)
      expect(DisciplineLessonPlan.exists?(discipline_lesson_plan.id)).to be(true)
    end

    it 'usa KNOWLEDGE_AREA_IDS quando informado' do
      other_area = create(:knowledge_area)
      other_discipline = create(:discipline, knowledge_area: other_area)
      create(
        :teacher_discipline_classroom,
        teacher: teacher,
        classroom: classroom,
        discipline: other_discipline
      )

      result = described_class.new(
        discipline_lesson_plan_ids: [discipline_lesson_plan.id],
        knowledge_area_ids: [knowledge_area.id, other_area.id],
        dry_run: false,
        skip_knowledge_area_check: true
      ).call

      expect(result.created).to eq(1)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaLessonPlan.last.knowledge_areas.map(&:id).sort)
        .to eq([knowledge_area.id, other_area.id].sort)
    end

    it 'remove o plano por disciplina quando delete_old é true' do
      described_class.new(
        discipline_lesson_plan_ids: [discipline_lesson_plan.id],
        dry_run: false,
        delete_old: true
      ).call

      expect(DisciplineLessonPlan.exists?(discipline_lesson_plan.id)).to be(false)
      expect(KnowledgeAreaLessonPlan.count).to eq(1)
    end

    it 'cria um plano por área para cada plano de disciplina, mesmo na mesma área e período' do
      other_discipline = create(:discipline, knowledge_area: knowledge_area)
      create(
        :teacher_discipline_classroom,
        teacher: teacher,
        classroom: classroom,
        discipline: other_discipline
      )
      other_lesson_plan = create(
        :lesson_plan,
        :with_teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: other_discipline,
        start_at: lesson_plan.start_at,
        end_at: lesson_plan.end_at,
        contents: [content],
        objectives: [objective]
      )
      other_discipline_lesson_plan = create(
        :discipline_lesson_plan,
        lesson_plan: other_lesson_plan,
        discipline: other_discipline,
        teacher_id: teacher.id
      )

      result = described_class.new(
        discipline_lesson_plan_ids: [discipline_lesson_plan.id, other_discipline_lesson_plan.id],
        dry_run: false
      ).call

      expect(result.created).to eq(2)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaLessonPlan.count).to eq(2)
      expect(KnowledgeAreaLessonPlan.all.flat_map { |plan| plan.knowledge_areas.map(&:id) }.uniq)
        .to eq([knowledge_area.id])
    end

    it 'retorna erro quando as áreas informadas não incluem a área da disciplina' do
      other_area = create(:knowledge_area)

      result = described_class.new(
        discipline_lesson_plan_ids: [discipline_lesson_plan.id],
        knowledge_area_ids: [other_area.id],
        dry_run: false
      ).call

      expect(result.created).to eq(0)
      expect(result.errors.first).to include('não incluem a área da disciplina')
    end
  end
end
