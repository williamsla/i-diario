module Navigation
  class ShortcutsBuilder
    def self.build(*args)
      new(*args).build
    end

    def initialize(user, render = ShortcutRender)
      @navigation_render = render.new(user)
      @navigation = defined?(MENU) ? MENU : Navigation::Base::MENU
    end

    def build
      shortcuts = amount_nodes(navigation).compact.flatten
      highlighted, regular = shortcuts.partition { |shortcut| shortcut['shortcut_highlight'] }
      shortcuts = highlighted + regular
      navigation_render.render(shortcuts)
    end

    protected

    attr_reader :navigation, :navigation_render

    def amount_nodes(nodes)
      nodes.map { |node|
        visible = node['menu']['visible']
        next if visible == 'only-when-aee' && !aee_navigation_context?
        next if visible == 'hide-when-aee' && aee_navigation_context?
        next unless node['menu']['shortcut']

        node_values(node['menu'])
      }
    end

    def node_values(node)
      if node['submenus']
        node['submenus'].map { |submenu|
          next unless submenu['menu']['shortcut']

          submenu['menu'].merge(node.slice('icon'))
        }.compact
      else
        node.slice('type', 'icon', 'path', 'shortcut_highlight')
      end
    end

    def aee_navigation_context?
      Thread.current[:navigation_is_aee]
    end
  end
end
