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

  describe '#fetch_students' do
    let(:form) do
      described_class.new(
        classroom_id: classroom.id,
        start_at: Date.new(classroom.year, 1, 1),
        end_at: Date.new(classroom.year, 12, 31)
      )
    end
    let(:grade_without_opinion) do
      create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::DONT_USE))
    end
    let(:grade_with_opinion) do
      create(:classrooms_grade, classroom: classroom, exam_rule: create(:exam_rule, opinion_type: OpinionTypes::BY_STEP))
    end
    let!(:student_without_opinion) do
      enrollment = create(:student_enrollment)
      create(:student_enrollment_classroom, classrooms_grade: grade_without_opinion, student_enrollment: enrollment)
      enrollment.student
    end
    let!(:student_with_opinion) do
      enrollment = create(:student_enrollment)
      create(:student_enrollment_classroom, classrooms_grade: grade_with_opinion, student_enrollment: enrollment)
      enrollment.student
    end

    it 'does not include students from grades without parecer in a multi-grade classroom' do
      students = form.fetch_students

      expect(students).to include(student_with_opinion)
      expect(students).not_to include(student_without_opinion)
    end
  end
end
