# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EducaMais::Config do
  let(:entity) { instance_double(Entity, name: 'municipio_a') }

  before do
    allow(described_class).to receive(:secrets).and_return(secrets)
    allow(described_class).to receive(:app_url).and_return('http://localhost:5173')
    Entity.current = entity
  end

  after do
    Entity.current = nil
  end

  describe '.enabled?' do
    context 'when entity names are not configured' do
      let(:secrets) { {} }

      it 'is enabled for any entity' do
        expect(described_class).to be_enabled
      end
    end

    context 'when entity names are configured' do
      let(:secrets) { { educamais_entity_names: %w[municipio_a municipio_b] } }

      it 'is enabled for allowed entities' do
        expect(described_class).to be_enabled
      end

      it 'is disabled for entities outside the list' do
        allow(entity).to receive(:name).and_return('municipio_c')

        expect(described_class).not_to be_enabled
      end

      it 'is disabled when current entity is missing' do
        Entity.current = nil

        expect(described_class).not_to be_enabled
      end
    end
  end
end
