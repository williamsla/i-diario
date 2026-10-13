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

  it 'renders the Educa+ shortcut with the name defined in the terms dictionary' do
    allow(subject).to receive(:can_show?) { |feature|
      %w[educamais pedagogical_trackings daily_frequencies].include?(feature.to_s)
    }
    allow(TermsDictionary).to receive(:educamais_display_name).and_return('Indicadores')

    html = subject.render(menus)

    expect(html).to include('Indicadores')
    expect(html).not_to include('Educa+')
  end
end
