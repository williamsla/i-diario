# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Navigation::ShortcutsBuilder do
  class FakeShortcutRender
    def initialize(_user); end

    def render(shortcuts)
      shortcuts
    end
  end

  let(:user) { double('User', current_school_year: Date.current.year) }

  it 'includes the optional holiday shortcut when there is a holiday in the current year' do
    allow(OptionalHoliday).to receive(:by_year).with(Date.current.year).and_return(double(exists?: true))

    types = described_class.build(user, FakeShortcutRender).map { |shortcut| shortcut['type'] }

    expect(types).to include('optional_holidays')
  end

  it 'does not include the optional holiday shortcut when there is no holiday in the current year' do
    allow(OptionalHoliday).to receive(:by_year).with(Date.current.year).and_return(double(exists?: false))

    types = described_class.build(user, FakeShortcutRender).map { |shortcut| shortcut['type'] }

    expect(types).not_to include('optional_holidays')
  end

  it 'includes Educa+ and Acompanhamento pedagógico as shortcut candidates' do
    allow(OptionalHoliday).to receive(:by_year).with(Date.current.year).and_return(double(exists?: false))

    types = described_class.build(user, FakeShortcutRender).map { |shortcut| shortcut['type'] }

    expect(types).to include('educamais', 'pedagogical_trackings')
  end

  it 'marks Educa+ and Acompanhamento pedagógico as highlighted shortcuts' do
    allow(OptionalHoliday).to receive(:by_year).with(Date.current.year).and_return(double(exists?: false))

    highlighted = described_class.build(user, FakeShortcutRender).select { |shortcut|
      shortcut['shortcut_highlight']
    }.map { |shortcut| shortcut['type'] }

    expect(highlighted).to include('educamais', 'pedagogical_trackings')
  end
end
