require 'rails_helper'

RSpec.describe DisciplineToKnowledgeAreaContentRecordMigrator do
  let(:classroom) { create(:classroom) }
  let(:teacher) { create(:teacher) }
  let(:knowledge_area) { create(:knowledge_area) }
  let(:discipline) { create(:discipline, knowledge_area: knowledge_area) }
  let(:content) { create(:content) }
  let(:content_record) do
    create(
      :content_record,
      classroom: classroom,
      teacher: teacher,
      record_date: Date.new(2025, 3, 10),
      contents: [content]
    )
  end
  let(:discipline_content_record) do
    create(:discipline_content_record, content_record: content_record, discipline: discipline)
  end

  before do
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: discipline
    )
  end

  describe '#call' do
    it 'simula a migração sem gravar quando dry_run é true' do
      result = described_class.new(
        discipline_record_ids: [discipline_content_record.id],
        dry_run: true
      ).call

      expect(result.created).to eq(1)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaContentRecord.count).to eq(0)
      expect(DisciplineContentRecord.exists?(discipline_content_record.id)).to be(true)
    end

    it 'cria registro por área usando a área da disciplina e mantém o registro por disciplina' do
      result = described_class.new(
        discipline_record_ids: [discipline_content_record.id],
        dry_run: false
      ).call

      expect(result.created).to eq(1)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaContentRecord.count).to eq(1)

      ka_content_record = KnowledgeAreaContentRecord.last
      expect(ka_content_record.knowledge_areas).to eq([knowledge_area])
      expect(ka_content_record.teacher_id).to eq(teacher.id)
      expect(ka_content_record.content_record.contents).to eq([content])
      expect(DisciplineContentRecord.exists?(discipline_content_record.id)).to be(true)
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
        discipline_record_ids: [discipline_content_record.id],
        knowledge_area_ids: [knowledge_area.id, other_area.id],
        dry_run: false,
        skip_knowledge_area_check: true
      ).call

      expect(result.created).to eq(1)
      expect(result.errors).to be_empty
      expect(KnowledgeAreaContentRecord.last.knowledge_areas.map(&:id).sort)
        .to eq([knowledge_area.id, other_area.id].sort)
    end

    it 'remove o registro por disciplina quando delete_old é true' do
      described_class.new(
        discipline_record_ids: [discipline_content_record.id],
        dry_run: false,
        delete_old: true
      ).call

      expect(DisciplineContentRecord.exists?(discipline_content_record.id)).to be(false)
      expect(KnowledgeAreaContentRecord.count).to eq(1)
    end

    it 'ignora quando já existe registro por área na mesma data e áreas' do
      existing_content_record = create(
        :content_record,
        classroom: classroom,
        teacher: teacher,
        record_date: content_record.record_date,
        contents: [content]
      )
      create(
        :knowledge_area_content_record,
        content_record: existing_content_record,
        knowledge_areas: [knowledge_area]
      )

      result = described_class.new(
        discipline_record_ids: [discipline_content_record.id],
        dry_run: false
      ).call

      expect(result.created).to eq(0)
      expect(result.skipped).to eq(1)
      expect(KnowledgeAreaContentRecord.count).to eq(1)
    end

    it 'retorna erro quando as áreas informadas não incluem a área da disciplina' do
      other_area = create(:knowledge_area)

      result = described_class.new(
        discipline_record_ids: [discipline_content_record.id],
        knowledge_area_ids: [other_area.id],
        dry_run: false
      ).call

      expect(result.created).to eq(0)
      expect(result.errors.first).to include('não incluem a área da disciplina')
    end
  end
end
