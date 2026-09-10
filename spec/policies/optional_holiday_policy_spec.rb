# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionalHolidayPolicy do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:unity) { create(:unity) }
  let(:holiday) do
    create(
      :optional_holiday,
      makeup_scope: OptionalHolidayMakeupScope::BY_SCHOOL
    )
  end

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  def grant_optional_holidays_permission(user)
    role = user.current_user_role.role
    role.permissions.find_or_initialize_by(feature: 'optional_holidays').tap do |permission|
      permission.permission = Permissions::CHANGE
      permission.save_without_auditing
    end
    user.reload
    user.current_user_role = user.user_roles.first
  end

  subject { described_class.new(user, holiday) }

  context 'when the user is an administrator' do
    let(:user) { create(:user, :with_user_role_administrator, admin: false, current_unity_id: unity.id) }

    before { grant_optional_holidays_permission(user) }

    it { expect(subject.update?).to eq(true) }
    it { expect(subject.create?).to eq(true) }
    it { expect(subject.destroy?).to eq(true) }
  end

  context 'when the user is a school employee' do
    let(:user) { create(:user, :with_user_role_employee, admin: false, current_unity_id: unity.id) }

    before { grant_optional_holidays_permission(user) }

    it 'allows informing the school makeup date when it is still pending' do
      expect(subject.update?).to eq(true)
    end

    it 'does not allow creating or destroying the optional holiday' do
      expect(subject.create?).to eq(false)
      expect(subject.destroy?).to eq(false)
    end

    it 'does not allow changing the holiday after the school makeup date was informed' do
      create(
        :optional_holiday_unity_makeup,
        optional_holiday: holiday,
        unity: unity
      )
      holiday.reload

      expect(subject.update?).to eq(false)
    end

    it 'does not allow updating a municipal optional holiday' do
      municipal = create(
        :optional_holiday,
        holiday_date: Date.current + 1.day,
        makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
      )

      expect(described_class.new(user, municipal).update?).to eq(false)
    end
  end
end
