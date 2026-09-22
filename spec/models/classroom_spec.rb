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

  describe '#early_childhood_or_aee?' do
    let(:classroom) { create(:classroom) }

    def link_grade(course_description, grade_description)
      course = create(:course, description: course_description)
      grade = create(:grade, course: course, description: grade_description)
      create(:classrooms_grade, classroom: classroom, grade: grade)
    end

    it 'reconhece educação infantil pelo curso' do
      link_grade('Educação Infantil', 'Maternal')

      expect(classroom.early_childhood_or_aee?).to eq(true)
    end

    it 'reconhece AEE pela série' do
      link_grade('Atendimento Educacional Especializado', 'AEE')

      expect(classroom.early_childhood_or_aee?).to eq(true)
    end

    it 'reconhece AEE pelo curso mesmo sem a sigla na série' do
      link_grade('Atendimento Educacional Especializado', 'Etapa única')

      expect(classroom.early_childhood_or_aee?).to eq(true)
    end

    it 'não reconhece turma do ensino fundamental' do
      link_grade('Ensino Fundamental', '3º ano')

      expect(classroom.early_childhood_or_aee?).to eq(false)
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
