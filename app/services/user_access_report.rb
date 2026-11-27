# frozen_string_literal: true

class UserAccessReport
  Row = Struct.new(:unity_id, :name, :count)
  Month = Struct.new(:label, :count)
  WITHOUT_UNITY = 'none'.freeze
  ALL_SCHOOLS = 'all'.freeze

  attr_reader :year

  def initialize(role_id, chart_unity_id: nil, allowed_role_ids: nil, school_id: :all, year: nil)
    @role_id = role_id
    @chart_unity_id = chart_unity_id
    @allowed_role_ids = allowed_role_ids
    @school_id = school_id
    @year = (year.presence || Date.current.year).to_i
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

    scope = UserRole.where(role_id: role.id).where(user_id: logins_in_year.select(:user_id))
    scope = scope_for_school(scope) if restricted_to_school?
    User.where(id: scope.select(:user_id)).count
  end

  def chart_school_name
    return unless chart_target
    return all_schools_label if chart_target == ALL_SCHOOLS
    return without_unity_label if chart_target == WITHOUT_UNITY

    chart_target.name
  end

  def chart_for_all?
    chart_target == ALL_SCHOOLS
  end

  def monthly_accesses
    monthly_series(year)
  end

  def previous_monthly_accesses
    monthly_series(year - 1)
  end

  def month_labels
    (1..12).map { |month| I18n.l(Date.new(year, month, 1), format: '%b') }
  end

  def chart_for?(row)
    return false unless chart_target
    return false if chart_target == ALL_SCHOOLS

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

  def all_schools_label
    I18n.t('user_access_reports.index.total')
  end

  def scope_for_school(scope)
    if role.student?
      scope.where(user_id: enrolled_users.where(classrooms: { unity_id: school_id }).select('users.id'))
    else
      scope.where(unity_id: school_id)
    end
  end

  def grouped_counts
    return student_grouped_counts if role.student?

    UserRole.where(role_id: role.id)
            .where(user_id: logins_in_year.select(:user_id))
            .left_joins(:unity)
            .group('unities.id', 'unities.name')
            .order('unities.name ASC NULLS LAST, unities.id ASC')
            .count('DISTINCT user_roles.user_id')
  end

  def student_grouped_counts
    relation = enrolled_users
    relation = relation.where(classrooms: { unity_id: school_id }) if restricted_to_school?

    counts = relation.group('unities.id', 'unities.name').count('DISTINCT users.id')
    counts = counts.sort_by { |(unity_id, unity_name), _count| [unity_name.to_s, unity_id.to_i] }.to_h
    return counts if restricted_to_school?

    missing = users_without_enrollment.count('DISTINCT user_roles.user_id')
    counts[[nil, nil]] = missing if missing.positive?
    counts
  end

  def enrolled_users(target_year = year)
    @enrolled_users_by_year ||= {}
    @enrolled_users_by_year[target_year] ||= enrolled_users_scope(target_year)
  end

  def enrolled_users_scope(target_year)
    start_on = format('%04d-01-01', target_year)
    finish_on = format('%04d-12-31', target_year)

    User.joins(:user_roles)
        .where(user_roles: { role_id: role.id })
        .where(id: logins_in_year(target_year).select(:user_id))
        .joins(student: {
          student_enrollments: {
            student_enrollment_classrooms: { classrooms_grade: { classroom: :unity } }
          }
        })
        .where(student_enrollments: { active: 1 })
        .where(classrooms: { year: target_year })
        .where('student_enrollment_classrooms.joined_at <= ?', finish_on)
        .where(
          "COALESCE(student_enrollment_classrooms.left_at, '') = '' OR student_enrollment_classrooms.left_at >= ?",
          start_on
        )
  end

  def users_without_enrollment(target_year = year)
    UserRole.where(role_id: role.id)
            .where(user_id: logins_in_year(target_year).select(:user_id))
            .where.not(user_id: enrolled_users(target_year).select('users.id'))
  end

  def chart_target
    return @chart_target if defined?(@chart_target)

    @chart_target = resolve_chart_target
  end

  def resolve_chart_target
    raw = chart_unity_id.to_s
    return if raw.blank?

    if raw == ALL_SCHOOLS
      return if restricted_to_school? && school_id.blank?

      return ALL_SCHOOLS
    end

    if restricted_to_school?
      return if school_id.blank?
      return own_school if raw == school_id.to_s

      return
    end

    return WITHOUT_UNITY if raw == WITHOUT_UNITY

    Unity.find_by(id: raw) if raw.match?(/\A\d+\z/)
  end

  def logins_in_year(target_year = year)
    UserLogin.where(year_sql, target_year)
  end

  def year_sql
    "EXTRACT(YEAR FROM user_logins.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo') = ?"
  end

  def monthly_series(target_year)
    return [] unless role && chart_target

    counts = logins_for_chart(target_year).group(month_sql).count('DISTINCT user_logins.id')
    build_series(counts, target_year)
  end

  def logins_for_chart(target_year)
    scope = logins_in_year(target_year).joins('INNER JOIN user_roles ON user_roles.user_id = user_logins.user_id')
                                        .where('user_roles.role_id = ?', role.id)
    return student_logins_for_chart(scope, target_year) if role.student?
    return logins_for_all_schools(scope) if chart_target == ALL_SCHOOLS
    return scope.where('user_roles.unity_id IS NULL') if chart_target == WITHOUT_UNITY

    scope.where('user_roles.unity_id = ?', chart_target.id)
  end

  def logins_for_all_schools(scope)
    return scope unless restricted_to_school?

    scope.where('user_roles.unity_id = ?', school_id)
  end

  def student_logins_for_chart(scope, target_year)
    return scope if chart_target == ALL_SCHOOLS && !restricted_to_school?
    return scope.where(user_id: users_without_enrollment(target_year).select(:user_id)) if chart_target == WITHOUT_UNITY

    unity_id = chart_target == ALL_SCHOOLS ? school_id : chart_target.id
    scope.where(user_id: enrolled_users(target_year).where(classrooms: { unity_id: unity_id }).select('users.id'))
  end

  def month_sql
    "to_char(user_logins.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM')"
  end

  def build_series(counts_by_month, target_year)
    (1..12).map do |month|
      date = Date.new(target_year, month, 1)
      key = date.strftime('%Y-%m')
      Month.new(I18n.l(date, format: '%b/%Y'), counts_by_month[key].to_i)
    end
  end
end
