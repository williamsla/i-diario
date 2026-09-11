require 'rails_helper'

RSpec.describe Classroom, type: :model do
  describe '#has_opinion_type?' do
    let(:classroom) { create(:classroom) }

    context 'when no classrooms_grades exist' do
      it 'returns false' do
        expect(classroom.has_opinion_type?).to eq(false)
      end
    end

    context 'when the only exam rule does not use parecer' do
      before do
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
      end

      it 'returns false' do
        expect(classroom.has_opinion_type?).to eq(false)
      end
    end

    context 'when a later grade in a multi-grade classroom uses parecer' do
      before do
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_STEP))
      end

      it 'returns true even if the first exam rule does not use parecer' do
        expect(classroom.first_exam_rule.opinion_type).to eq(OpinionTypes::DONT_USE)
        expect(classroom.has_opinion_type?).to eq(true)
      end
    end

    context 'when only the differentiated exam rule uses parecer' do
      before do
        differentiated = create(:exam_rule, opinion_type: OpinionTypes::BY_YEAR)
        exam_rule = create(:exam_rule, opinion_type: OpinionTypes::DONT_USE, differentiated_exam_rule: differentiated)
        create(:classrooms_grade, classroom: classroom, exam_rule: exam_rule)
      end

      it 'returns true' do
        expect(classroom.has_opinion_type?).to eq(true)
      end
    end
  end

  describe '#descriptive_opinion_types' do
    let(:classroom) { create(:classroom) }

    it 'returns only opinion types that allow descriptive exam' do
      create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
      create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_YEAR))

      expect(classroom.descriptive_opinion_types).to eq([OpinionTypes::BY_YEAR])
    end
  end
end
