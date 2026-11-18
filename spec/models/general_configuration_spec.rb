require 'rails_helper'

RSpec.describe GeneralConfiguration, :type => :model do
  context "Validations" do
    it { should validate_presence_of :security_level }
    it { should validate_presence_of :allows_after_sales_relationship }

    it { should allow_value(SecurityLevels::BASIC).for(:security_level) }
    it { should allow_value(SecurityLevels::ADVANCED).for(:security_level) }
    it { should_not allow_value("nana").for(:security_level) }
  end

  describe ".current" do
    context "when it has a persited configuration" do
      it "return the first persited configuration" do
        general_configuration = general_configurations(:general_configuration)
        expect(GeneralConfiguration.current).to eq general_configuration
      end
    end

    it "não reaproveita a configuração em cache de outro município" do
      first_configuration = general_configurations(:general_configuration)
      other_configuration = GeneralConfiguration.new

      allow(Entity).to receive(:current).and_return(instance_double(Entity, id: 1))
      allow(GeneralConfiguration).to receive(:first).and_return(first_configuration)
      expect(GeneralConfiguration.current).to eq first_configuration

      allow(Entity).to receive(:current).and_return(instance_double(Entity, id: 2))
      allow(GeneralConfiguration).to receive(:first).and_return(other_configuration)
      expect(GeneralConfiguration.current).to eq other_configuration
    end
  end

  describe "#mark_with_error" do
    it "sets configuration backup's error message" do
      error = ""

      expect(subject).to receive(:update_columns).with(
        backup_status: ApiSynchronizationStatus::ERROR,
        error_message: error
      )

      subject.mark_with_error!(error)
    end
  end
end
