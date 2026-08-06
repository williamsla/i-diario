require 'rails_helper'

RSpec.describe KnowledgeAreaToDisciplineContentRecordMigrator do
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
  let(:ka_content_record) do
    create(:knowledge_area_content_record, content_record: content_record, knowledge_areas: [knowledge_area])
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
        ka_record_ids: [ka_content_record.id],
        discipline_id: discipline.id,
        dry_run: true
      ).call

      expect(result.created).to eq(1)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty
      expect(DisciplineContentRecord.count).to eq(0)
      expect(KnowledgeAreaContentRecord.exists?(ka_content_record.id)).to be(true)
    end

    it 'cria registro por disciplina e mantém o registro por área por padrão' do
      result = described_class.new(
        ka_record_ids: [ka_content_record.id],
        discipline_id: discipline.id,
        dry_run: false
      ).call

      expect(result.created).to eq(1)
      expect(result.errors).to be_empty
      expect(DisciplineContentRecord.count).to eq(1)

      discipline_content_record = DisciplineContentRecord.last
      expect(discipline_content_record.discipline_id).to eq(discipline.id)
      expect(discipline_content_record.teacher_id).to eq(teacher.id)
      expect(discipline_content_record.content_record.contents).to eq([content])
      expect(KnowledgeAreaContentRecord.exists?(ka_content_record.id)).to be(true)
    end

    it 'remove o registro por área quando delete_old é true' do
      described_class.new(
        ka_record_ids: [ka_content_record.id],
        discipline_id: discipline.id,
        dry_run: false,
        delete_old: true
      ).call

      expect(KnowledgeAreaContentRecord.exists?(ka_content_record.id)).to be(false)
      expect(DisciplineContentRecord.count).to eq(1)
    end

    it 'ignora quando já existe registro por disciplina na mesma data' do
      existing_content_record = create(
        :content_record,
        classroom: classroom,
        teacher: teacher,
        record_date: content_record.record_date,
        contents: [content]
      )
      create(
        :discipline_content_record,
        content_record: existing_content_record,
        discipline: discipline
      )

      result = described_class.new(
        ka_record_ids: [ka_content_record.id],
        discipline_id: discipline.id,
        dry_run: false
      ).call

      expect(result.created).to eq(0)
      expect(result.skipped).to eq(1)
      expect(DisciplineContentRecord.count).to eq(1)
    end

    it 'retorna erro quando a disciplina não pertence à área do registro' do
      other_discipline = create(:discipline)

      create(
        :teacher_discipline_classroom,
        teacher: teacher,
        classroom: classroom,
        discipline: other_discipline
      )

      result = described_class.new(
        ka_record_ids: [ka_content_record.id],
        discipline_id: other_discipline.id,
        dry_run: false
      ).call

      expect(result.created).to eq(0)
      expect(result.errors.first).to include('não pertence às áreas do registro')
    end
  end
end
