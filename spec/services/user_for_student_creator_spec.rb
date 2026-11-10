require 'rails_helper'
require 'cpf_cnpj'

RSpec.describe UserForStudentCreator, type: :service do
  let!(:student_role) { create(:role, access_level: AccessLevel::STUDENT) }
  let(:student) { create(:student, name: 'Maria Souza', api_code: 'portal9001') }

  it 'cria o usuário com o CPF e a senha do boletim' do
    user = described_class.sync!(student.id, '529.982.247-25')

    expect(user).to be_persisted
    expect(user.cpf).to eq('529.982.247-25')
    expect(user.valid_password?('maria@529')).to be(true)
    expect(user.student_id).to eq(student.id)
    expect(user.reload.roles.pluck(:access_level)).to include(AccessLevel::STUDENT)
  end

  it 'troca a senha antiga quando o CPF chega na sincronização' do
    user = described_class.sync!(student.id, nil)

    expect(user.valid_password?('estudanteportal9001')).to be(true)

    described_class.sync!(student.id, '52998224725')

    expect(user.reload.cpf).to eq('529.982.247-25')
    expect(user.valid_password?('maria@529')).to be(true)
  end

  it 'não troca a senha que a família já alterou' do
    user = described_class.sync!(student.id, '52998224725')
    user.password = 'senhanova'
    user.password_confirmation = 'senhanova'
    user.save!(validate: false)

    described_class.sync!(student.id, '52998224725')

    expect(user.reload.valid_password?('senhanova')).to be(true)
  end

  it 'não grava um CPF que já pertence a outro usuário' do
    document = CPF.generate
    create(:user, cpf: CPF.new(document).formatted)

    user = described_class.sync!(student.id, document)

    expect(user.cpf).to be_blank
    expect(user.valid_password?('estudanteportal9001')).to be(true)
  end
end
