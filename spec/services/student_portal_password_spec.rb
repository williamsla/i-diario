require 'rails_helper'

RSpec.describe StudentPortalPassword, type: :service do
  it 'monta a senha com o primeiro nome e os três primeiros dígitos do CPF' do
    password = described_class.for(name: 'Maria Souza', cpf: '123.456.789-00')

    expect(password).to eq('maria@123')
  end

  it 'remove acento e ignora o restante do nome' do
    password = described_class.for(name: 'José Almeida', cpf: '52998224725')

    expect(password).to eq('jose@529')
  end

  it 'mantém o zero à esquerda do CPF' do
    password = described_class.for(name: 'João Pedro Lima', cpf: '084.111.222-33')

    expect(password).to eq('joao@084')
  end

  it 'usa quatro dígitos quando o primeiro nome tem uma letra' do
    password = described_class.for(name: 'I Silva', cpf: '12345678900')

    expect(password).to eq('i@1234')
  end

  it 'usa a primeira parte de um nome com hífen' do
    password = described_class.for(name: 'Ana-Beatriz Souza', cpf: '12345678900')

    expect(password).to eq('ana@123')
  end
end
