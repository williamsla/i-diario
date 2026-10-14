require 'rails_helper'

RSpec.describe User, type: :model do
  context 'associations' do
    it { expect(subject).to belong_to(:current_user_role).class_name('UserRole') }

    it { expect(subject).to have_many(:logins) }
    it { expect(subject).to have_many(:synchronizations) }
    it { expect(subject).to have_many(:user_roles) }
    it { expect(subject).to have_and_belong_to_many(:students) }
  end

  context 'validations' do
    it { expect(subject).to_not validate_presence_of(:student) }

    it { expect(subject).to allow_value('').for(:phone) }
    it { expect(subject).to allow_value('(33) 33445566').for(:phone) }
    it { expect(subject).to allow_value('(33) 334445556').for(:phone) }
    it { expect(subject).to_not allow_value('(33) 3344-5565').for(:phone) }
    it { expect(subject).to_not allow_value('(33) 3344-556').for(:phone) }
    it { expect(subject).to_not allow_value('(33) 3344556').for(:phone) }

    it { expect(subject).to allow_value(nil).for(:cpf) }
    it { expect(subject).to allow_value('531.880.033-58').for(:cpf) }
    it { expect(subject).to_not allow_value('531.880.033-5').for(:cpf) }
    it { expect(subject).to_not allow_value('531.880.033-587').for(:cpf) }

    it { expect(subject).to allow_value('admin@example.com').for(:email) }
    it { expect(subject).to_not allow_value('admin@examplecom', 'adminexample.com').for(:email).with_message('use apenas letras (a-z), números e pontos.') }

    context 'when without email and without cpf' do
      it 'should require email or cpf' do
        subject.email = nil
        subject.cpf = nil

        subject.valid?

        expect(subject.errors[:base]).to include('Necessário informar e-mail ou CPF')
      end
    end

    context 'when with email and without cpf' do
      it 'should not require email or cpf' do
        subject.email = 'user@example.com'
        subject.cpf = nil

        subject.valid?

        expect(subject.errors[:base]).not_to include('Necessário informar e-mail ou CPF')
      end
    end

    context 'when without email and with cpf' do
      it 'should not require email or cpf' do
        subject.email = nil
        subject.cpf = Faker::CPF.pretty

        subject.valid?

        expect(subject.errors[:base]).not_to include('Necessário informar e-mail ou CPF')
      end
    end
  end

  describe '#authorize_email_and_sms' do
    it 'have false as default value' do
      expect(subject.authorize_email_and_sms).to eq(false)
    end
  end

  describe '#update_tracked_fields!' do
    it 'for every login it will log the user ip' do
      ip = '127.0.0.1'
      request = double(remote_ip: ip).as_null_object

      expect(subject.logins).to receive(:create!).with(sign_in_ip: ip)

      subject.update_tracked_fields!(request)
    end
  end

  describe '#to_s' do
    context 'without name' do
      before do
        subject.first_name = ''
        subject.email = 'foo@bar.com'
      end

      it 'returns the email' do
        expect(subject.to_s).to eql('foo@bar.com')
      end
    end

    context 'with name' do
      before do
        subject.first_name = 'Foo'
        subject.last_name = 'Bar'
      end

      it 'returns the name' do
        expect(subject.to_s).to eql('Foo Bar')
      end
    end
  end

  describe '#active_for_authentication?' do
    it 'can not authenticate if status is pending' do
      subject.status = UserStatus::PENDING

      expect(subject).to_not be_active_for_authentication
    end

    it 'can authenticate if status is active' do
      subject.status = UserStatus::ACTIVE

      expect(subject).to be_active_for_authentication
    end
  end

  describe '#set_current_user_role!' do
    subject { create(:user) }

    it 'updates the #current_user_role_id' do
      user_role = create(:user_role)
      subject.user_roles << user_role

      expect {
        subject.set_current_user_role!(user_role.id)
      }.to change { subject.current_user_role_id }.from(nil).to(user_role.id)
    end
  end

  describe '#can_show?' do
    it 'hides Educa+ in shortcuts when the permission is Não or Sem acesso' do
      user = create(:user, admin: true)
      role = create(:role, :administrator)
      create(:role_permission, role: role, feature: Features::EDUCAMAIS, permission: Permissions::READ)
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:educamais)).to eq(false)

      user.current_user_role.role.permissions.find_by(feature: 'educamais').update!(permission: Permissions::DENIED)
      user.reload

      expect(user.can_show?(:educamais)).to eq(false)
    end

    it 'shows Educa+ when the permission is Sim' do
      user = create(:user, admin: true)
      role = create(:role, :administrator)
      create(:role_permission, role: role, feature: Features::EDUCAMAIS, permission: Permissions::CHANGE)
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:educamais)).to eq(true)
    end

    it 'shows Educa+ and Acompanhamento pedagógico only when the role permission is enabled' do
      user = create(:user, admin: false)
      role = create(:role, :administrator)
      create(:role_permission, role: role, feature: Features::PEDAGOGICAL_TRACKINGS, permission: Permissions::CHANGE)
      create(:role_permission, role: role, feature: Features::EDUCAMAIS, permission: Permissions::DENIED)
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:pedagogical_trackings)).to eq(true)
      expect(user.can_show?(:educamais)).to eq(false)
    end

    it 'hides Acompanhamento pedagógico when the role permission is denied' do
      user = create(:user, admin: false)
      role = create(:role, :administrator)
      create(:role_permission, role: role, feature: Features::PEDAGOGICAL_TRACKINGS, permission: Permissions::DENIED)
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:pedagogical_trackings)).to eq(false)
    end

    it 'follows the role permission for registro de atendimento AEE even when the user is admin' do
      user = create(:user, admin: true)
      role = create(:role, :administrator)
      create(:role_permission, role: role, feature: 'aee_attendance_records', permission: Permissions::DENIED)
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:aee_attendance_records)).to eq(false)
      expect(user.can_change?(:aee_attendance_records)).to eq(false)
    end

    it 'hides planos de ensino por áreas de conhecimento when the administrator profile has no access' do
      user = create(:user, admin: true)
      role = create(:role, :administrator)
      create(
        :role_permission,
        role: role,
        feature: 'knowledge_area_teaching_plans',
        permission: Permissions::DENIED
      )
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:knowledge_area_teaching_plans)).to eq(false)
      expect(user.can_change?(:knowledge_area_teaching_plans)).to eq(false)
    end

    it 'shows registro de atendimento AEE for the administrator profile when the permission allows it' do
      user = create(:user, admin: true)
      role = create(:role, :administrator)
      create(:role_permission, role: role, feature: 'aee_attendance_records', permission: Permissions::CHANGE)
      user_role = create(:user_role, user: user, role: role)
      user.update!(current_user_role: user_role)
      user.reload

      expect(user.can_show?(:aee_attendance_records)).to eq(true)
      expect(user.can_change?(:aee_attendance_records)).to eq(true)
    end
  end
end
