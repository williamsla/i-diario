# frozen_string_literal: true

class RecordAuditTrailTeacherLinks
  Option = Struct.new(:id, :name, :text) do
    def to_s
      name
    end
  end

  def self.links_for(classroom_id:, teacher_id: nil, year:)
    scope = TeacherDisciplineClassroom.unscoped.where(classroom_id: classroom_id, year: year)
    scope = scope.where(teacher_id: teacher_id) if teacher_id.present?
    scope
  end

  def self.current?(link)
    link.active && link.kept? && !link.left?
  end

  def self.teachers_for_select(classroom_id, year)
    links = links_for(classroom_id: classroom_id, year: year).to_a
    return [] if links.blank?

    links.group_by(&:teacher_id).map do |teacher_id, teacher_links|
      teacher = Teacher.find_by(id: teacher_id)
      next if teacher.blank?

      label = teacher.name
      unless teacher_links.any? { |link| current?(link) }
        label = I18n.t('services.record_audit_trail_teacher_links.unlinked_option', name: teacher.name)
      end

      Option.new(teacher.id, label, label)
    end.compact.sort_by(&:name)
  end

  def self.discipline_ids_for(classroom_id:, teacher_id:, year:)
    links_for(classroom_id: classroom_id, teacher_id: teacher_id, year: year).pluck(:discipline_id)
  end

  def self.allocation(classroom_id:, teacher_id:, year:)
    return nil if classroom_id.blank? || teacher_id.blank?

    links = links_for(classroom_id: classroom_id, teacher_id: teacher_id, year: year).to_a
    current = links.select { |link| current?(link) }
    former = links - current

    status = if current.present?
               'linked'
             elsif former.present?
               'unlinked'
             else
               'missing'
             end

    {
      status: status,
      current_count: current.size,
      former_count: former.size,
      left_at: former.map(&:left_at).compact.min,
      discarded_at: former.map(&:discarded_at).compact.max,
      teacher_name: Teacher.find_by(id: teacher_id)&.to_s,
      classroom_name: Classroom.find_by(id: classroom_id)&.to_s
    }
  end
end
