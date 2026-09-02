# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TermsDictionary, type: :model do
  describe 'validations' do
    it { is_expected.to validate_length_of(:educamais_label).is_at_most(TermsDictionary::EDUCAMAIS_LABEL_MAX_LENGTH) }
    it { is_expected.to allow_value('').for(:educamais_label) }
    it { is_expected.to allow_value(nil).for(:educamais_label) }
  end

  it 'strips whitespace from educamais_label' do
    subject.presence_identifier_character = '.'
    subject.educamais_label = '  Indicadores  '
    subject.valid?

    expect(subject.educamais_label).to eq('Indicadores')
  end

  describe '.educamais_display_name' do
    after { Entity.current = nil }

    it 'returns Educa+ when there is no current entity' do
      Entity.current = nil

      expect(described_class.educamais_display_name).to eq('Educa+')
    end

    it 'returns the custom label defined for the municipality' do
      Entity.current = instance_double(Entity, id: 1)
      allow(described_class).to receive(:cached_current)
        .and_return(described_class.new(educamais_label: 'Indicadores'))

      expect(described_class.educamais_display_name).to eq('Indicadores')
    end

    it 'returns Educa+ when the custom label is blank' do
      Entity.current = instance_double(Entity, id: 1)
      allow(described_class).to receive(:cached_current)
        .and_return(described_class.new(educamais_label: '   '))

      expect(described_class.educamais_display_name).to eq('Educa+')
    end
  end
end
