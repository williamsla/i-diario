# frozen_string_literal: true

require 'rails_helper'

describe Navigation::Render::Base do
  let(:user) { instance_double(User, admin?: false, can_show?: false) }

  subject { described_class.new(user) }

  describe '#can_show?' do
    it 'shows Educa+ when the user has permission' do
      allow(user).to receive(:can_show?).with('educamais').and_return(true)

      expect(subject.send(:can_show?, 'educamais')).to eq(true)
    end

    it 'hides Educa+ when the user does not have permission' do
      allow(user).to receive(:can_show?).with('educamais').and_return(false)

      expect(subject.send(:can_show?, 'educamais')).to eq(false)
    end

    it 'shows Acompanhamento pedagógico when the user has permission' do
      allow(user).to receive(:can_show?).with('pedagogical_trackings').and_return(true)

      expect(subject.send(:can_show?, 'pedagogical_trackings')).to eq(true)
    end

    it 'hides Acompanhamento pedagógico when the user does not have permission' do
      allow(user).to receive(:can_show?).with('pedagogical_trackings').and_return(false)

      expect(subject.send(:can_show?, :pedagogical_trackings)).to eq(false)
    end
  end
end
