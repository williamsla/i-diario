require 'rails_helper'

RSpec.describe CurrentProfile do
  describe '#initialize' do
    let(:user) do
      instance_double(
        User,
        current_school_year: 2026,
        current_user_role: nil,
        current_unity: nil,
        current_classroom: nil,
        current_teacher: nil,
        current_discipline: nil
      )
    end

    it 'accepts ActionController::Parameters without converting them via with_indifferent_access' do
      params = ActionController::Parameters.new(by_school_year: 2025)

      expect(params).not_to receive(:with_indifferent_access)

      profile = described_class.new(user, params)

      expect(profile.school_year).to eq(2025)
    end

    it 'keeps hash access indifferent for regular hashes' do
      profile = described_class.new(user, 'by_school_year' => 2024)

      expect(profile.school_year).to eq(2024)
    end
  end

  describe '#disciplines_as_json' do
    let(:teacher) { create(:teacher) }
    let(:classroom) { create(:classroom) }
    let(:user) { create(:user, teacher: teacher) }
    let(:fundamental_grade) { create(:grade, course: create(:course, description: 'Ensino Fundamental'), description: '5º Ano') }
    let(:infantil_grade) { create(:grade, course: create(:course, description: 'Educação Infantil'), description: 'Jardim') }
    let(:fundamental_discipline) { create(:discipline, description: 'Arte') }
    let(:infantil_discipline) { create(:discipline, description: 'Identidade e Autonomia') }
    let(:profile) do
      described_class.new(user, by_classroom_id: classroom.id, by_teacher_id: teacher.id)
    end

    before do
      Entity.current = Entity.first
      Rails.cache.clear

      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: fundamental_discipline,
        grade: fundamental_grade
      )
      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: infantil_discipline,
        grade: infantil_grade
      )
    end

    after { Entity.current = nil }

    it 'separa disciplina e área de conhecimento pela série da alocação' do
      kinds = profile.disciplines_as_json.map { |item| [item['discipline_id'], item['record_kind']] }

      expect(kinds).to include(
        [fundamental_discipline.id, 'discipline'],
        [infantil_discipline.id, 'knowledge_area']
      )
    end

    it 'mantém o bloco quando o nome da disciplina muda' do
      infantil_discipline.update!(description: 'Campo renomeado')
      Rails.cache.clear

      option = profile.disciplines_as_json.find { |item| item['discipline_id'] == infantil_discipline.id }

      expect(option['description']).to eq('Campo renomeado')
      expect(option['record_kind']).to eq('knowledge_area')
    end

    it 'marca a disciplina alocada nos dois tipos de série' do
      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: infantil_discipline,
        grade: fundamental_grade
      )
      Rails.cache.clear

      option = profile.disciplines_as_json.find { |item| item['discipline_id'] == infantil_discipline.id }

      expect(option['record_kind']).to eq('both')
    end
  end
end
