module Navigation
  class Base
    def self.menu
      path = Rails.root.join('config', 'navigation.yml')
      mtime = path.mtime.to_i

      if @menu_mtime != mtime
        @menu = YAML.safe_load(ERB.new(path.read).result)['navigation']
        @menu_mtime = mtime
      end

      @menu
    end

    def self.build(*args)
      new(*args).build
    end

    def initialize(item, user, render = Navigation::Render::Base)
      @item = item.to_s
      @navigation_render = render.new(user)
      @navigation = self.class.menu
    end

    def build
    end

    protected

    attr_reader :navigation, :item, :navigation_render

    def menus
      @menus ||= []
    end
  end
end

