require 'rails_helper'

RSpec.describe DescriptiveReportForm do
  let(:classroom) { create(:classroom) }
  let(:form) { described_class.new(classroom_id: classroom.id) }

  describe '#opinion_type_by_discipline?' do
    context 'when the first grade does not use parecer and another uses by discipline' do
      before do
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
        create(
          :classrooms_grade,
          classroom: classroom,
          exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_STEP_AND_DISCIPLINE)
        )
      end

      it 'returns true' do
        expect(form.opinion_type_by_discipline?).to eq(true)
      end
    end

    context 'when no grade uses parecer by discipline' do
      before do
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_STEP))
      end

      it 'returns false' do
        expect(form.opinion_type_by_discipline?).to eq(false)
      end
    end
  end

  describe '#is_annual' do
    context 'when the first grade does not use parecer and another is annual' do
      before do
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_YEAR))
      end

      it 'returns true' do
        expect(form.is_annual).to eq(true)
      end
    end

    context 'when the grade with parecer is by step' do
      before do
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
        create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_STEP))
      end

      it 'returns false' do
        expect(form.is_annual).to eq(false)
      end
    end
  end
end
