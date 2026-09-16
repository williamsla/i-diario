require 'rails_helper'

RSpec.describe EntityConfiguration, :type => :model do
  describe ".current" do
    context "when it doesn't have a existent configuration" do
      it "returns a new configuration" do
        expect(EntityConfiguration.current).to be_new_record
      end
    end

    context "when it has a persited configuration" do
      it "return the first persited configuration" do
        entity_configuration = EntityConfiguration.create
        expect(EntityConfiguration.current).to eq entity_configuration
      end
    end
  end

  describe '#ibge_code' do
    it 'accepts a 7-digit IBGE code' do
      config = EntityConfiguration.new(ibge_code: '2304400')
      config.valid?
      expect(config.ibge_code).to eq('2304400')
      expect(config.errors[:ibge_code]).to be_empty
    end

    it 'strips non-digits before validating' do
      config = EntityConfiguration.new(ibge_code: '2.304.400')
      config.valid?
      expect(config.ibge_code).to eq('2304400')
    end

    it 'rejects codes that are not 7 digits' do
      config = EntityConfiguration.new(ibge_code: '123')
      expect(config).not_to be_valid
      expect(config.errors[:ibge_code]).to be_present
    end
  end
end
