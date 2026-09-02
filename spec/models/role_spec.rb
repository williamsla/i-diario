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

  describe "#default_permission_for" do
    it "grants Educa+ and Acompanhamento pedagógico to administrator roles" do
      role = build(:role, :administrator)

      expect(role.default_permission_for('pedagogical_trackings')).to eq(Permissions::CHANGE)
      expect(role.default_permission_for('educamais')).to eq(Permissions::CHANGE)
    end

    it "grants Educa+ and Acompanhamento pedagógico to employee roles" do
      role = build(:role, access_level: AccessLevel::EMPLOYEE)

      expect(role.default_permission_for('pedagogical_trackings')).to eq(Permissions::CHANGE)
      expect(role.default_permission_for('educamais')).to eq(Permissions::CHANGE)
    end

    it "denies Acompanhamento pedagógico to teacher roles by default" do
      role = build(:role, :teacher)

      expect(role.default_permission_for('pedagogical_trackings')).to eq(Permissions::DENIED)
    end
  end
end
