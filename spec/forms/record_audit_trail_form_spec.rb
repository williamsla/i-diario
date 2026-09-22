require 'rails_helper'

RSpec.describe RecordAuditTrailForm, type: :model do
  describe 'filtro de educação infantil e AEE' do
    let(:area) { create(:knowledge_area, description: 'Corpo, gestos e movimentos', group_descriptors: false) }
    let(:discipline) do
      create(:discipline, knowledge_area: area, description: 'Eixo 1', grouper: false, descriptor: false)
    end
    let(:sibling) do
      create(:discipline, knowledge_area: area, description: 'Eixo 2', grouper: true, descriptor: false)
    end

    def classroom_for(course_description, grade_description)
      course = create(:course, description: course_description)
      grade = create(:grade, course: course, description: grade_description)
      create(:classroom).tap do |classroom|
        create(:classrooms_grade, classroom: classroom, grade: grade)
      end
    end

    it 'mostra o nome da área e uma opção por área' do
      classroom = classroom_for('Educação Infantil', 'Maternal')
      form = described_class.new(classroom_id: classroom.id, discipline_id: discipline.id)

      expect(form.discipline_filter_label).to eq('Área de conhecimento')
      expect(form.discipline_filter_value).to eq('Corpo, gestos e movimentos')

      options = described_class.discipline_options([discipline, sibling], classroom)

      expect(options.map(&:name)).to eq(['Corpo, gestos e movimentos'])
      expect(options.map(&:id)).to eq([sibling.id])

      selected = described_class.discipline_options([discipline, sibling], classroom, discipline.id)

      expect(selected.map(&:id)).to eq([discipline.id])
      expect(selected.map(&:name)).to eq(['Corpo, gestos e movimentos'])
    end

    it 'mostra o nome da área em turma AEE' do
      classroom = classroom_for('Atendimento Educacional Especializado', 'Etapa única')
      form = described_class.new(classroom_id: classroom.id, discipline_id: discipline.id)

      expect(form.discipline_filter_label).to eq('Área de conhecimento')
      expect(form.discipline_filter_value).to eq('Corpo, gestos e movimentos')
    end

    it 'mantém o nome da disciplina nas demais turmas' do
      classroom = classroom_for('Ensino Fundamental', '3º ano')
      form = described_class.new(classroom_id: classroom.id, discipline_id: discipline.id)

      expect(form.discipline_filter_label).to eq('Disciplina')
      expect(form.discipline_filter_value).to eq('Eixo 1')

      options = described_class.discipline_options([discipline, sibling], classroom)

      expect(options.map(&:name)).to contain_exactly('Eixo 1', 'Eixo 2')
    end
  end
end
