require 'rails_helper'

RSpec.describe PedagogicalTrackingGradeRecordTypes, type: :service do
  let(:year) { Date.current.year }
  let(:unity) { create(:unity) }
  let(:other_unity) { create(:unity) }
  let(:course) { create(:course, description: 'Ensino Fundamental') }
  let(:grade) { create(:grade, course: course, description: '1º ANO') }
  let(:other_grade) { create(:grade, course: course, description: '2º ANO') }
  let(:classroom) { create(:classroom, unity: unity, year: year) }
  let(:other_classroom) { create(:classroom, unity: other_unity, year: year) }
  let(:teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:knowledge_area) { create(:knowledge_area) }

  before do
    create(:classrooms_grade, classroom: classroom, grade: grade)
    create(:classrooms_grade, classroom: other_classroom, grade: other_grade)
    create(:school_calendar, :with_one_step, unity: unity, year: year)
    create(:school_calendar, :with_one_step, unity: other_unity, year: year)
  end

  def create_content_record_for(target_classroom)
    create(
      :content_record,
      :with_contents,
      classroom: target_classroom,
      teacher: teacher,
      record_date: Date.current
    )
  end

  def create_discipline_record(target_classroom)
    create(
      :discipline_content_record,
      content_record: create_content_record_for(target_classroom),
      discipline: discipline
    )
  end

  def create_knowledge_area_record(target_classroom)
    create(
      :knowledge_area_content_record,
      content_record: create_content_record_for(target_classroom),
      knowledge_areas: [knowledge_area]
    )
  end

  describe '#call' do
    it 'returns an empty hash when no grades are given' do
      expect(described_class.new(year: year, grade_ids: []).call).to eq({})
    end

    it 'classifies a grade with only discipline records' do
      create_discipline_record(classroom)

      result = described_class.new(year: year, grade_ids: [grade.id, other_grade.id]).call

      expect(result[grade.id]).to eq(described_class::DISCIPLINE)
      expect(result[other_grade.id]).to eq(described_class::NONE)
    end

    it 'classifies a grade with only knowledge area records' do
      create_knowledge_area_record(classroom)

      result = described_class.new(year: year, grade_ids: [grade.id]).call

      expect(result[grade.id]).to eq(described_class::KNOWLEDGE_AREA)
    end

    it 'classifies a grade that used both record types' do
      create_discipline_record(classroom)
      create_knowledge_area_record(classroom)

      result = described_class.new(year: year, grade_ids: [grade.id]).call

      expect(result[grade.id]).to eq(described_class::BOTH)
    end

    it 'ignores records from another year' do
      past_classroom = create(:classroom, unity: unity, year: year - 1)
      create(:classrooms_grade, classroom: past_classroom, grade: grade)
      create_discipline_record(past_classroom)

      result = described_class.new(year: year, grade_ids: [grade.id]).call

      expect(result[grade.id]).to eq(described_class::NONE)
    end

    it 'restricts results to the given unities' do
      create_discipline_record(classroom)
      create_knowledge_area_record(other_classroom)

      result = described_class.new(
        year: year,
        grade_ids: [grade.id, other_grade.id],
        unity_ids: [unity.id]
      ).call

      expect(result[grade.id]).to eq(described_class::DISCIPLINE)
      expect(result[other_grade.id]).to eq(described_class::NONE)
    end
  end
end
