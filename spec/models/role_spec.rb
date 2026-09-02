# encoding: utf-8
require 'rails_helper'

RSpec.describe Role, :type => :model do
  context "Associations" do
    it { should belong_to :author }
    it { should have_many :permissions }
  end

  context "Validations" do
    it { should validate_presence_of :author }
    it { should validate_presence_of :name }

    it "should validate permissions must match access level" do
      subject.access_level = AccessLevel::TEACHER

      subject.permissions.build(feature: Features::USERS, permission: Permissions::CHANGE)

      subject.valid?

      expect(subject.errors[:permissions]).to eq ["Funcionalidade Usuários não pertence ao nível de acesso Professor."]
    end
  end

  describe "#to_s" do
    it "returns name" do
      subject.name = "administrador"
      subject.access_level = AccessLevel::TEACHER

      expect(subject.to_s).to eq "administrador - Nível: Professor"
    end
  end

  describe "#permissions_cache_key" do
    let(:role) { create(:role, :administrator) }

    it "changes when a permission value changes" do
      permission = create(
        :role_permission,
        role: role,
        feature: Features::PEDAGOGICAL_TRACKINGS,
        permission: Permissions::DENIED
      )

      original_key = role.permissions_cache_key

      permission.update!(permission: Permissions::READ)

      expect(Role.find(role.id).permissions_cache_key).not_to eq(original_key)
    end
  end

end
