# frozen_string_literal: true

require 'rails_helper'

describe Navigation::ShortcutRender, type: :service do
  let(:current_user) { User.new(admin: true) }

  subject { described_class.new(current_user) }

  let(:menus) do
    [
      {
        'type' => 'educamais',
        'icon' => 'fa-bar-chart',
        'path' => 'educamais_launch_path',
        'shortcut_highlight' => true
      },
      {
        'type' => 'pedagogical_trackings',
        'icon' => 'fa-line-chart',
        'path' => 'pedagogical_trackings_path',
        'shortcut_highlight' => true
      },
      {
        'type' => 'daily_frequencies',
        'icon' => 'fa-check-square-o',
        'path' => 'new_daily_frequency_path'
      }
    ]
  end

  it 'renders Educa+ and Acompanhamento pedagógico when the user can see them' do
    allow(subject).to receive(:can_show?) { |feature|
      %w[educamais pedagogical_trackings daily_frequencies].include?(feature.to_s)
    }

    html = subject.render(menus)

    expect(html).to include('Educa+')
    expect(html).to include('Acompanhamento pedagógico')
    expect(html).to include('educamais')
    expect(html).to include('acompanhamento-pedagogico')
  end

  it 'hides Educa+ and Acompanhamento pedagógico when the user cannot see them' do
    allow(subject).to receive(:can_show?).and_return(false)
    allow(subject).to receive(:can_show?).with('daily_frequencies').and_return(true)

    html = subject.render(menus)

    expect(html).not_to include('Educa+')
    expect(html).not_to include('Acompanhamento pedagógico')
  end

  it 'renders Acompanhamento pedagógico for Administrator profile' do
    user = User.new(admin: false)
    allow(user).to receive(:administrator?).and_return(true)
    allow(EducaMais::Config).to receive(:enabled?).and_return(true)

    html = described_class.new(user).render(menus)

    expect(html).to include('Acompanhamento pedagógico')
    expect(html).to include('Educa+')
  end
end
