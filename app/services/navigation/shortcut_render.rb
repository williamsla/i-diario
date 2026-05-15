module Navigation
  class ShortcutRender < Navigation::Render::Base
    def render(menus)
      menus = menus.select { |menu| can_show? menu['type'] }

      raw menus.map { |menu| render_menu(menu.with_indifferent_access) }.join(' ')
    end

    protected

    def render_menu(menu)
      css_classes = %w[col-sm-4 col-md-2 col-lg-2 col-xs-6 text-center shortcut]
      css_classes << 'shortcut--highlight' if menu[:shortcut_highlight]

      content_tag :div, class: css_classes.join(' ') do
        link_to(path_method(menu[:path])) do
          text = content_tag(:i, '', class: "shortcut-icon fa fa-lg fa-fw #{menu[:icon]}")
          text + content_tag(:span, menu_text(menu[:type]), class: '')
        end
      end
    end
  end
end
