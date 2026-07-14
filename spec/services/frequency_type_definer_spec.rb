require 'rails_helper'

RSpec.describe FrequencyTypeDefiner do
  let(:exam_rule) { create(:exam_rule, frequency_type: FrequencyTypes::GENERAL) }
  let(:classroom) { create(:classroom) }
  let!(:classrooms_grade) { create(:classrooms_grade, classroom: classroom, exam_rule: exam_rule) }
  let(:teacher) { create(:teacher) }
  let(:general_discipline) { create(:discipline) }
  let(:specific_discipline) { create(:discipline) }

  before do
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: general_discipline,
      grade: classrooms_grade.grade,
      year: classroom.year,
      allow_absence_by_discipline: 0,
      active: true
    )
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: specific_discipline,
      grade: classrooms_grade.grade,
      year: classroom.year,
      allow_absence_by_discipline: 1,
      active: true
    )
  end

  describe '#define!' do
    context 'quando a disciplina do perfil é do vínculo geral' do
      subject(:definer) do
        described_class.new(
          classroom,
          teacher.id,
          exam_rule,
          year: classroom.year,
          discipline_id: general_discipline.id
        )
      end

      it 'mantém frequência geral mesmo existindo outro vínculo por disciplina na turma' do
        definer.define!

        expect(definer.frequency_type).to eq(FrequencyTypes::GENERAL)
      end
    end

    context 'quando a disciplina do perfil é do vínculo por disciplina' do
      subject(:definer) do
        described_class.new(
          classroom,
          teacher.id,
          exam_rule,
          year: classroom.year,
          discipline_id: specific_discipline.id
        )
      end

      it 'define frequência por disciplina' do
        definer.define!

        expect(definer.frequency_type).to eq(FrequencyTypes::BY_DISCIPLINE)
      end
    end

    context 'quando não informa disciplina' do
      subject(:definer) do
        described_class.new(
          classroom,
          teacher.id,
          exam_rule,
          year: classroom.year
        )
      end

      it 'promove para por disciplina se existir qualquer vínculo específico' do
        definer.define!

        expect(definer.frequency_type).to eq(FrequencyTypes::BY_DISCIPLINE)
      end
    end
  end
end
