module Navigation
  class ShortcutsBuilder
    OPTIONAL_HOLIDAYS_SHORTCUT = 'only-when-optional-holidays'.freeze

    def self.build(*args)
      new(*args).build
    end

    def initialize(user, render = ShortcutRender)
      @user = user
      @navigation_render = render.new(user)
      @navigation = Navigation::Base::MENU
    end

    def build
      shortcuts = amount_nodes(navigation).compact.flatten
      highlighted, regular = shortcuts.partition { |shortcut| shortcut['shortcut_highlight'] }
      shortcuts = highlighted + regular
      navigation_render.render(shortcuts)
    end

    protected

    attr_reader :navigation, :navigation_render, :user

    def amount_nodes(nodes)
      nodes.map { |node|
        visible = node['menu']['visible']
        next if visible == 'only-when-aee' && !aee_navigation_context?
        next unless shortcut_enabled?(node['menu']['shortcut'])

        node_values(node['menu'])
      }
    end

    def node_values(node)
      if node['submenus']
        node['submenus'].map { |submenu|
          next unless shortcut_enabled?(submenu['menu']['shortcut'])

          submenu['menu'].merge(node.slice('icon'))
        }.compact
      else
        node.slice('type', 'icon', 'path', 'shortcut_highlight')
      end
    end

    def shortcut_enabled?(value)
      return true if value == true
      return optional_holidays_exist_for_current_year? if value.to_s == OPTIONAL_HOLIDAYS_SHORTCUT

      false
    end

    def optional_holidays_exist_for_current_year?
      year = user.try(:current_school_year)
      return false if year.blank?

      OptionalHoliday.by_year(year).exists?
    end

    def aee_navigation_context?
      Thread.current[:navigation_is_aee]
    end
  end
end
