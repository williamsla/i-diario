require 'rails_helper'

RSpec.describe RecordAuditTrailTeacherLinks, type: :service do
  let(:teacher) { create(:teacher) }
  let(:classroom) { create(:classroom) }
  let(:discipline) { create(:discipline) }
  let!(:link) do
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: discipline,
      year: classroom.year
    )
  end

  describe '.teachers_for_select' do
    it 'lista professora ativa sem sufixo' do
      options = described_class.teachers_for_select(classroom.id, classroom.year)

      expect(options.map(&:id)).to eq([teacher.id])
      expect(options.first.name).to eq(teacher.name)
    end

    it 'mantém professora no combo após vínculo encerrado' do
      link.discard

      options = described_class.teachers_for_select(classroom.id, classroom.year)

      expect(options.map(&:id)).to eq([teacher.id])
      expect(options.first.name).to eq(
        I18n.t('services.record_audit_trail_teacher_links.unlinked_option', name: teacher.name)
      )
    end
  end

  describe '.allocation' do
    it 'marca vínculo vigente' do
      allocation = described_class.allocation(
        classroom_id: classroom.id,
        teacher_id: teacher.id,
        year: classroom.year
      )

      expect(allocation[:status]).to eq('linked')
    end

    it 'marca vínculo encerrado após discard' do
      link.discard

      allocation = described_class.allocation(
        classroom_id: classroom.id,
        teacher_id: teacher.id,
        year: classroom.year
      )

      expect(allocation[:status]).to eq('unlinked')
      expect(allocation[:discarded_at]).to be_present
    end

    it 'marca vínculo encerrado após data de saída' do
      link.update_columns(end_at: Date.yesterday)

      allocation = described_class.allocation(
        classroom_id: classroom.id,
        teacher_id: teacher.id,
        year: classroom.year
      )

      expect(allocation[:status]).to eq('unlinked')
      expect(allocation[:left_at]).to eq(Date.yesterday)
    end

    it 'marca ausência de vínculo quando nunca houve alocação' do
      other_teacher = create(:teacher)

      allocation = described_class.allocation(
        classroom_id: classroom.id,
        teacher_id: other_teacher.id,
        year: classroom.year
      )

      expect(allocation[:status]).to eq('missing')
    end
  end

  describe '.discipline_ids_for' do
    it 'inclui disciplina do vínculo encerrado' do
      link.discard

      ids = described_class.discipline_ids_for(
        classroom_id: classroom.id,
        teacher_id: teacher.id,
        year: classroom.year
      )

      expect(ids).to include(discipline.id)
    end
  end
end
