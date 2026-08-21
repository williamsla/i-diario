require 'rails_helper'

RSpec.describe AeeCaseStudyPdf, type: :report do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  let(:unity) { create(:unity) }
  let(:entity_configuration) { create(:entity_configuration, entity_name: 'Rede municipal', organ_name: 'SME') }
  let(:student) { create(:student, name: 'Aluno do estudo de caso') }
  let(:aee_case_study) do
    create(
      :aee_case_study,
      unity: unity,
      student: student,
      grade_stage: '3º Ano',
      age: '11 anos',
      identification: 'Deficiência intelectual',
      modality: 'Ensino Fundamental',
      individual_demands: 'Demandas observadas',
      barriers_and_context: 'Barreiras do contexto',
      potentialities_and_support: 'Potencialidades registradas',
      accessibility_strategies: 'Estratégias definidas',
      final_considerations: 'Encaminhamentos finais',
      specialized_teacher_name: 'NOME_QUE_NAO_DEVE_APARECER'
    )
  end

  it 'renders identification, stages and blank signature lines' do
    pdf = described_class.build(entity_configuration, aee_case_study).render
    text = PDF::Inspector::Text.analyze(pdf).strings.join(' ')

    expect(text).to include('Estudo de caso do estudante')
    expect(text).to include(student.name)
    expect(text).to include('3º Ano')
    expect(text).to include('11 anos')
    expect(text).to include('Ensino Fundamental')
    expect(text).to include('Demandas observadas')
    expect(text).to include('Barreiras do contexto')
    expect(text).to include('Potencialidades registradas')
    expect(text).to include('Estratégias definidas')
    expect(text).to include('Encaminhamentos finais')
    expect(text).to include(AeeCaseStudy.human_attribute_name(:regular_teacher_name))
    expect(text).to include(AeeCaseStudy.human_attribute_name(:specialized_teacher_name))
    expect(text).to include('_______________________________________')
    expect(text).not_to include('NOME_QUE_NAO_DEVE_APARECER')
  end
end
