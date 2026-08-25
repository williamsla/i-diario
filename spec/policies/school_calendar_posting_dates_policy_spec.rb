# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarPostingDatesPolicy do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) { create(:user, :with_user_role_administrator, admin: false) }
  let(:role) { user.current_user_role.role }

  subject { described_class.new(user, SchoolCalendarPostingDates) }

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  before do
    role.permissions.find_or_initialize_by(feature: 'school_calendar_posting_dates').tap do |permission|
      permission.permission = permission_value
      permission.save_without_auditing
    end
    user.reload
    user.current_user_role = user.user_roles.first
  end

  context 'when the administrator can change the feature' do
    let(:permission_value) { Permissions::CHANGE }

    it { expect(subject.edit?).to eq(true) }
    it { expect(subject.update?).to eq(true) }
  end

  context 'when the administrator cannot change the feature' do
    let(:permission_value) { Permissions::DENIED }

    it { expect(subject.edit?).to eq(false) }
    it { expect(subject.update?).to eq(false) }
  end

  context 'when the user is not an administrator' do
    let(:permission_value) { Permissions::CHANGE }
    let(:user) { create(:user, :with_user_role_teacher, admin: false) }

    it { expect(subject.edit?).to eq(false) }
  end
end
