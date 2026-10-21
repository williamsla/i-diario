class TeacherUnificationsSynchronizer < BaseSynchronizer
  def synchronize!
    update_teacher_unifications(
      HashDecorator.new(
        api.fetch(ignore_modified: true)['unificacoes']
      )
    )
  rescue IeducarApi::Base::ApiError => error
    synchronization.mark_as_error!(error.message)
  end

  private

  def api_class
    IeducarApi::TeacherUnifications
  end

  def update_teacher_unifications(unifications)
    unifications.each do |unification|
      next if unification.main_id.blank?

      teacher = teacher(unification.main_id) || teacher(unification.main_id.to_s)

      next if teacher.blank?

      update_teacher_unification(teacher, unification)
    end
  end

  def update_teacher_unification(teacher, unification)
    secondary_teachers = duplicate_api_codes(unification).map { |api_code|
      teacher(api_code)
    }.compact
    secondary_teachers = secondary_teachers.reject { |secondary_teacher| secondary_teacher.id == teacher.id }

    active = ActiveRecord::Type::Boolean.new.cast(unification.active)
    teacher_unification = TeacherUnification.find_or_initialize_by(teacher_id: teacher.id)
    new_record = teacher_unification.new_record?
    teacher_unification.unified_at = unification.created_at
    teacher_unification.active = active
    state_changed = teacher_unification.changed?
    teacher_unification.save! if state_changed

    secondary_teachers.each do |secondary_teacher|
      teacher_unification.unified_teachers.find_or_create_by!(teacher: secondary_teacher)
    end

    if active
      pending_teachers = secondary_teachers.select(&:kept?)
      return if pending_teachers.empty?

      TeacherUnification::UnificationService.new(teacher, pending_teachers).run!
    elsif state_changed && !new_record
      TeacherUnification::ReverterService.new(teacher, secondary_teachers).run!
    end
  end

  def duplicate_api_codes(unification)
    extract_duplicate_values(unification.duplicates_id).flatten.compact.map { |value|
      duplicate_api_code(value)
    }.reject(&:blank?).uniq
  end

  def extract_duplicate_values(raw)
    case raw
    when Array
      raw
    when String
      parsed_duplicate_string(raw)
    when Hash
      raw.values
    when NilClass
      []
    else
      raw.respond_to?(:to_h) ? raw.to_h.values : [raw]
    end
  end

  def parsed_duplicate_string(raw)
    parsed = JSON.parse(raw)
    parsed.is_a?(Array) ? parsed : [parsed]
  rescue JSON::ParserError
    raw.split(',')
  end

  def duplicate_api_code(value)
    code = if value.is_a?(Hash)
             value['id'] || value[:id] || value.values.first
           elsif !value.is_a?(Numeric) && !value.is_a?(String) && value.respond_to?(:id)
             value.id
           else
             value
           end

    code.to_s.strip
  end
end
