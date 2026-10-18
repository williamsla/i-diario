module Navigation
  class MenuBuilder < Base
    def initialize(item, user, render = MenuRender)
      @navigation_user = user
      super(item, user, render)
    end

    def build
      amount_menus
      render
    end

    protected

    def amount_menus
      amount_nodes navigation do |menu|
        menus << menu
      end
    end

    def amount_nodes(nodes, parent_menu = nil)
      nodes ||= []

      nodes.select do |node|
        visible = node["menu"]["visible"]
        next if (!visible.nil? && visible == false) || (visible == 'only-when-active' && node["menu"]["type"] != item)
        next if visible == 'only-when-aee' && !aee_navigation_context?
        next if visible == 'only-when-pei' && !pei_navigation_available?
        next if visible == 'hide-when-aee' && aee_navigation_context?
        next if visible == 'hide-when-aee-attendance-allowed' && aee_navigation_context? && aee_attendance_records_allowed?
        yield node_values(node["menu"], parent_menu)
      end
    end

    def node_values(node, parent_menu)
      {}.tap do |menu|
        menu[:type]      = node["type"]
        menu[:icon]      = node["icon"]
        menu[:path]      = node["path"]
        menu[:visible]   = node["visible"] == true || node["visible"] == 'only-when-active'
        menu[:css_class] = []
        menu[:subnodes]  = []

        if menu[:type] == item
          menu[:css_class] << :current
          parent_menu[:css_class] << :open if parent_menu
        end

        node["submenus"] ||= []
        amount_nodes node["submenus"], menu do |subnode|
          menu[:subnodes] << subnode
        end
        true
      end
    end

    def render
      navigation_render.render(menus)
    end

    def aee_navigation_context?
      Thread.current[:navigation_is_aee]
    end

    def pei_navigation_available?
      Thread.current[:navigation_pei_available]
    end

    def aee_attendance_records_allowed?
      navigation_user.respond_to?(:can_show?) && navigation_user.can_show?('aee_attendance_records')
    end

    attr_reader :navigation_user
  end
end
