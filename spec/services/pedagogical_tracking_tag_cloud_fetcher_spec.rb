require 'rails_helper'

RSpec.describe PedagogicalTrackingTagCloudFetcher, type: :service do
  let(:year) { Date.current.year }
  let(:unity) { create(:unity) }
  let(:other_unity) { create(:unity) }
  let(:course) { create(:course, description: 'Ensino Fundamental') }
  let(:grade) { create(:grade, course: course, description: '1º ANO') }
  let(:classroom) { create(:classroom, unity: unity, year: year) }
  let(:other_classroom) { create(:classroom, unity: other_unity, year: year) }
  let(:teacher) { create(:teacher) }
  let(:knowledge_area) { create(:knowledge_area, description: 'Matemática') }
  let(:other_knowledge_area) { create(:knowledge_area, description: 'Linguagens') }
  let(:discipline) { create(:discipline, knowledge_area: knowledge_area, description: 'Matemática') }
  let(:other_discipline) { create(:discipline, knowledge_area: other_knowledge_area, description: 'Português') }
  let(:content) { create(:content, description: 'Adição de frações') }
  let(:other_content) { create(:content, description: 'Leitura de contos') }

  before do
    create(:classrooms_grade, classroom: classroom, grade: grade)
    create(:classrooms_grade, classroom: other_classroom, grade: grade)
    create(:school_calendar, :with_one_step, unity: unity, year: year)
    create(:school_calendar, :with_one_step, unity: other_unity, year: year)
  end

  def create_content_record_for(target_classroom, contents, record_date: Date.current)
    create(
      :content_record,
      classroom: target_classroom,
      teacher: teacher,
      record_date: record_date,
      contents: contents
    )
  end

  def create_discipline_record(target_classroom, target_discipline, contents)
    create(
      :discipline_content_record,
      content_record: create_content_record_for(target_classroom, contents),
      discipline: target_discipline
    )
  end

  def create_knowledge_area_record(target_classroom, target_knowledge_area, contents)
    create(
      :knowledge_area_content_record,
      content_record: create_content_record_for(target_classroom, contents),
      knowledge_areas: [target_knowledge_area]
    )
  end

  describe '#fetch' do
    it 'returns empty clouds when no subject is given' do
      result = described_class.new(grade_id: grade.id, year: year).fetch

      expect(result).to eq(contents: [], objectives: [])
    end

    it 'returns contents from discipline records without mixing knowledge area records' do
      create_discipline_record(classroom, discipline, [content])
      create_knowledge_area_record(classroom, knowledge_area, [other_content])

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        discipline_id: discipline.id
      ).fetch

      expect(result[:contents].map { |tag| tag[:label] }).to eq([content.description])
      expect(result[:contents].first[:count]).to eq(1)
    end

    it 'returns contents from knowledge area records without mixing discipline records' do
      create_discipline_record(classroom, discipline, [content])
      create_knowledge_area_record(classroom, knowledge_area, [other_content])

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        knowledge_area_id: knowledge_area.id
      ).fetch

      expect(result[:contents].map { |tag| tag[:label] }).to eq([other_content.description])
      expect(result[:contents].first[:count]).to eq(1)
    end

    it 'does not include contents from another discipline' do
      create_discipline_record(classroom, discipline, [content])
      create_discipline_record(classroom, other_discipline, [other_content])

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        discipline_id: discipline.id
      ).fetch

      expect(result[:contents].map { |tag| tag[:label] }).to eq([content.description])
    end

    it 'does not include contents from another knowledge area' do
      create_knowledge_area_record(classroom, knowledge_area, [content])
      create_knowledge_area_record(classroom, other_knowledge_area, [other_content])

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        knowledge_area_id: knowledge_area.id
      ).fetch

      expect(result[:contents].map { |tag| tag[:label] }).to eq([content.description])
    end

    it 'groups equivalent content descriptions' do
      similar_content = create(:content, description: 'Adição de frações.')
      create_discipline_record(classroom, discipline, [content])
      create(
        :discipline_content_record,
        content_record: create_content_record_for(classroom, [similar_content], record_date: Date.current - 1.day),
        discipline: discipline
      )

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        discipline_id: discipline.id
      ).fetch

      expect(result[:contents].size).to eq(1)
      expect(result[:contents].first[:count]).to eq(2)
    end

    it 'filters by unity when unity_id is given' do
      create_discipline_record(classroom, discipline, [content])
      create_discipline_record(other_classroom, discipline, [other_content])

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        discipline_id: discipline.id,
        unity_id: unity.id
      ).fetch

      expect(result[:contents].map { |tag| tag[:label] }).to eq([content.description])
    end

    it 'does not include records from another year' do
      past_classroom = create(:classroom, unity: unity, year: year - 1)
      create(:classrooms_grade, classroom: past_classroom, grade: grade)
      create_discipline_record(past_classroom, discipline, [content])

      result = described_class.new(
        grade_id: grade.id,
        year: year,
        discipline_id: discipline.id
      ).fetch

      expect(result[:contents]).to eq([])
    end
  end
end
