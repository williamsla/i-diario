# frozen_string_literal: true

class UserAccessReport
  Row = Struct.new(:unity_id, :name, :count)
  Month = Struct.new(:label, :count)
  WITHOUT_UNITY = 'none'.freeze

  def initialize(role_id, chart_unity_id: nil, allowed_role_ids: nil, school_id: :all)
    @role_id = role_id
    @chart_unity_id = chart_unity_id
    @allowed_role_ids = allowed_role_ids
    @school_id = school_id
  end

  def role
    return @role if defined?(@role)

    @role = lookup_role
  end

  def rows
    return [] unless role
    return [] if restricted_to_school? && school_id.blank?

    list = grouped_counts.map do |(unity_id, unity_name), count|
      Row.new(unity_id, unity_name.presence || without_unity_label, count)
    end
    list = list.select { |row| row.unity_id == school_id } if restricted_to_school?
    list << empty_school_row if restricted_to_school? && list.empty? && own_school
    list
  end

  def total
    return 0 unless role
    return 0 if restricted_to_school? && school_id.blank?

    scope = UserRole.where(role_id: role.id).where(user_id: UserLogin.select(:user_id))
    scope = scope.where(unity_id: school_id) if restricted_to_school?
    User.where(id: scope.select(:user_id)).count
  end

  def chart_school_name
    return unless chart_target

    chart_target == WITHOUT_UNITY ? without_unity_label : chart_target.name
  end

  def monthly_accesses
    return [] unless role && chart_target

    counts = logins_for_chart.group(month_sql).count('DISTINCT user_logins.id')
    build_series(counts)
  end

  def chart_for?(row)
    return false unless chart_target

    if chart_target == WITHOUT_UNITY
      row.unity_id.nil?
    else
      row.unity_id == chart_target.id
    end
  end

  private

  attr_reader :role_id, :chart_unity_id, :allowed_role_ids, :school_id

  def lookup_role
    return if role_id.blank?

    found = Role.find_by(id: role_id)
    return if found.blank?
    return if allowed_role_ids && !allowed_role_ids.include?(found.id)

    found
  end

  def restricted_to_school?
    school_id != :all
  end

  def own_school
    return if school_id.blank? || school_id == :all

    @own_school ||= Unity.find_by(id: school_id)
  end

  def empty_school_row
    Row.new(own_school.id, own_school.name, 0)
  end

  def without_unity_label
    I18n.t('user_access_reports.index.without_unity')
  end

  def grouped_counts
    UserRole.where(role_id: role.id)
            .where(user_id: UserLogin.select(:user_id))
            .left_joins(:unity)
            .group('unities.id', 'unities.name')
            .order('unities.name ASC NULLS LAST, unities.id ASC')
            .count('DISTINCT user_roles.user_id')
  end

  def chart_target
    return @chart_target if defined?(@chart_target)

    @chart_target = resolve_chart_target
  end

  def resolve_chart_target
    raw = chart_unity_id.to_s
    return if raw.blank?

    if restricted_to_school?
      return if school_id.blank?
      return own_school if raw == school_id.to_s

      return
    end

    return WITHOUT_UNITY if raw == WITHOUT_UNITY

    Unity.find_by(id: raw) if raw.match?(/\A\d+\z/)
  end

  def logins_for_chart
    scope = UserLogin.joins('INNER JOIN user_roles ON user_roles.user_id = user_logins.user_id')
                     .where('user_roles.role_id = ?', role.id)

    if chart_target == WITHOUT_UNITY
      scope.where('user_roles.unity_id IS NULL')
    else
      scope.where('user_roles.unity_id = ?', chart_target.id)
    end
  end

  def month_sql
    "to_char(user_logins.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM')"
  end

  def build_series(counts_by_month)
    return [] if counts_by_month.blank?

    start_month = Date.strptime(counts_by_month.keys.min, '%Y-%m')
    finish = Date.current.beginning_of_month
    cursor = start_month
    series = []

    while cursor <= finish
      key = cursor.strftime('%Y-%m')
      series << Month.new(I18n.l(cursor, format: '%b/%Y'), counts_by_month[key].to_i)
      cursor = cursor.next_month
    end

    series
  end
end
