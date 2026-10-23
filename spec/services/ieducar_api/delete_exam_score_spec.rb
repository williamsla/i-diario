require 'rails_helper'

RSpec.describe IeducarApi::DeleteExamScore, type: :service do
  subject(:api) do
    described_class.new(
      url: 'https://ieducar.test',
      access_key: 'access',
      secret_key: 'secret',
      unity_id: 1
    )
  end

  it 'asks the legacy diary API to delete the score' do
    expect(api).to receive(:fetch).with(
      hash_including(
        path: 'module/Avaliacao/diarioApi',
        resource: 'nota',
        oper: 'delete',
        etapa: 1,
        matricula_id: '99',
        componente_curricular_id: '7',
        ignore_modified: true
      )
    )

    api.send_delete(etapa: 1, matricula_id: '99', componente_curricular_id: '7')
  end

  it 'requires the enrollment' do
    expect {
      api.send_delete(etapa: 1, componente_curricular_id: '7')
    }.to raise_error(IeducarApi::Base::ApiError, 'É necessário informar a matrícula')
  end
end
