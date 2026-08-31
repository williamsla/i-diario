module ApplicationHelper
  include ActiveSupport::Inflector
  include AeeHelper

  DEFAULT_LOGO = 'brasil.png'.freeze
  PROFILE_DEFAULT_PICTURE_PATH = '/assets/profile-default.jpg'.freeze

  def unread_notifications_count
    @unread_notifications_count ||= current_user.unread_notifications.count
  end

  def last_system_notifications
    has_notification = SystemNotificationTarget.where(user: current_user).exists?
    @last_system_notifications ||= has_notification ? current_user.system_notifications.limit(10).ordered : []
  end

  def system_notification_path(notification)
    SystemNotificationRouter.path(notification)
  end

  def unities
    @unities ||= Unity.ordered
  end

  def resource
    instance_variable_get("@#{controller_name.singularize}")
  end

  def tagfy(value)
    transliterate(value).tr(' ', '_').underscore
  end

  def breadcrumbs
    Navigation.draw_breadcrumbs(controller_name, self)
  end

  def menus
    role = current_user.current_user_role&.role
    user_role_cache = role&.cache_key.to_s + role&.id.to_s
    key = [
      'Menus',
      Entity.current&.id,
      current_user.admin?,
      controller_name,
      user_role_cache || current_user.cache_key,
      role&.permissions_cache_key,
      Translation.cache_key,
      is_aee
    ]

    Rails.cache.fetch(key, expires_in: 1.day) do
      begin
        Thread.current[:navigation_is_aee] = is_aee
        Navigation.draw_menus(controller_name, current_user)
      ensure
        Thread.current[:navigation_is_aee] = nil
      end
    end
  end

  def shortcuts
    role = current_user.current_user_role&.role
    key = [
      'HomeShortcutsV5',
      Entity.current&.id,
      current_user.admin?,
      navigation_cache_version,
      role&.cache_key || current_user&.cache_key,
      role&.permissions_cache_key,
      Translation.cache_key,
      is_aee,
      current_user.current_school_year,
      optional_holidays_shortcut_cache_token
    ]

    cached = Rails.cache.read(key)
    return cached if cached.present?

    html = begin
      Thread.current[:navigation_is_aee] = is_aee
      Navigation.draw_shortcuts(current_user)
    ensure
      Thread.current[:navigation_is_aee] = nil
    end
    # Nunca grava HTML vazio: evita esconder atalhos válidos por cache contaminado
    Rails.cache.write(key, html, expires_in: 1.day) if html.present?
    html
  end

  def navigation_cache_version
    @navigation_cache_version ||= Digest::MD5.file(
      Rails.root.join('config', 'navigation.yml')
    ).hexdigest
  end

  def optional_holidays_shortcut_cache_token
    year = current_user.current_school_year
    return 'none' if year.blank?

    OptionalHoliday.by_year(year).exists? ? "oh-#{year}-1" : "oh-#{year}-0"
  end

  def title
    Navigation.draw_title(controller_name, false, self)
  end

  def title_with_icon
    Navigation.draw_title(controller_name, true, self)
  end

  def simple_form_for(object, *args, &block)
    options = args.extract_options!
    options[:builder] ||= Portabilis::FormBuilder

    super object, *(args << options), &block
  end

  def profile_picture_tag(user, profile_picture_html_options = {})
    user_avatar_url = user_avatar_url(user)

    return unless user_avatar_url

    image_tag(user_avatar_url, profile_picture_html_options.merge(onerror: on_error_img, alt: ''))
  end

  def user_avatar_url(user)
    user_avatar = user.profile_picture&.url
    student_avatar = user.student&.avatar_url.to_s
    cache_key = [:user_avatar_url, current_entity.id, user.id, user_avatar, student_avatar]
    Rails.cache.fetch cache_key, expires_in: 1.day do
      user_avatar ||
        IeducarAvatarAuth.new(student_avatar).generate_new_url.presence ||
        PROFILE_DEFAULT_PICTURE_PATH
    end
  end

  def on_error_img
    "this.error=null;this.src='#{PROFILE_DEFAULT_PICTURE_PATH}'"
  end

  def custom_date_format(date)
    if date == Time.zone.today
      t('date.today')
    elsif date == Time.zone.yesterday
      t('date.yesterday')
    elsif date.year == Time.zone.today.year
      l(date, format: :short)
    else
      l(date, format: :long)
    end
  end

  def filename(file)
    file.path.split('/').last
  end

  def t_boolean(value)
    value ? t('boolean.yes') : t('boolean.no')
  end

  def number_of_classes_elements(number_of_classes)
    elements = []
    (1..number_of_classes).each do |i|
      elements << { id: i, name: i, text: i }
    end
    elements.to_json
  end

  def decimal_input_mask(number_of_decimal_places)
    if number_of_decimal_places
      { data: { inputmask: "'digits': #{number_of_decimal_places}" } }
    else
      { data: { inputmask: "'digits': 0" } }
    end
  end

  def entity_copyright
    Rails.cache.fetch("#{Entity.current.try(:id)}_entity_copyright", expires_in: 1.day) do
      "© #{GeneralConfiguration.current.copyright_name} #{Time.zone.today.year}"
    end
  end

  def entity_website
    Rails.cache.fetch("#{Entity.current.try(:id)}_entity_website", expires_in: 1.day) do
      GeneralConfiguration.current.support_url
    end
  end

  def alert_by_entity(_entity_name)
    ''
  end

  def initial_value_for_select2_remote(id, description)
    '{"id": ' + id.to_s + ', "description": "' + description.tr("\n", ' ') + '"}'
  end

  def link_to_if_and_else(*args, &block)
    condition = args.shift
    content = capture(&block)

    if condition
      link_to(*args) do
        content
      end
    else
      content
    end
  end

  def present(model)
    klass = "#{model.class}Presenter".constantize
    presenter = klass.new(model, self)

    yield(presenter) if block_given?
  end

  def back_link(name, path)
    content_for :back_link do
      back_link_tag(name, path)
    end
  end

  def back_link_tag(name, path)
    link_to path, class: 'back-link' do
      raw <<-HTML
        <i class="icon-append fa fa-angle-left"></i>
        #{name}
      HTML
    end
  end

  def window_state
    current_profile = CurrentProfile.new(current_user)

    {
      current_role: current_profile.user_role_as_json,
      available_roles: current_profile.user_roles_as_json,
      current_unity: current_profile.unity_as_json,
      available_unities: current_profile.unities_as_json,
      current_school_year: current_profile.school_year_as_json,
      available_school_years: current_profile.school_years_as_json,
      current_classroom: current_profile.classroom_as_json,
      available_classrooms: current_profile.classrooms_as_json,
      current_teacher: current_profile.teacher_as_json,
      available_teachers: current_profile.teachers_as_json,
      current_discipline: current_profile.discipline_as_json,
      available_disciplines: current_profile.disciplines_as_json,
      teacher_id: current_user.teacher_id,
      current_profile: current_profile.teacher_profile_as_json,
      profiles: current_profile.teacher_profiles_as_json,
      profile_complete: current_profile.complete?

    }
  end

  EXPERIENCE_FIELD_BADGE_COLORS = 5

  def experience_field_badge_class(experience_fields)
    return if experience_fields.blank?

    index = experience_fields.to_s.codepoints.sum % EXPERIENCE_FIELD_BADGE_COLORS
    "experience-field-badge experience-field-badge--color-#{index}"
  end

  private

  def cache_key_to_user
    [current_entity.id, current_user.id]
  end

  def logo_url
    # Sempre usa a logo da entidade atual (por domínio), em todos os ambientes,
    # para que cada município/tenant exiba sua própria logo.
    current_entity_configuration.try(:logo_url) || DEFAULT_LOGO
  end
end
