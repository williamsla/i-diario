class TeacherUnification
  class UnificationService < Base
    def run!
      @secondary_teachers.each do |secondary_teacher|
        ActiveRecord::Base.transaction do
          move_associations(secondary_teacher)
          discard(secondary_teacher) unless User.where(teacher_id: secondary_teacher.id).exists?
        end
      end
    end

    def move_associations(secondary_teacher)
      Teacher.reflect_on_all_associations(:has_many).each do |association|
        next if KEEP_ASSOCIATIONS.include?(association.name)
        next if association.options[:through].present?

        secondary_teacher.send(association.name).each do |record|
          unify(record, association)
        end
      end
    end

    def unify(record, association)
      return if association.name == :users && user_link_taken?(record)

      # see TeacherRelationable callback set_teacher_id
      record.teacher = @main_teacher if record.class.included_modules.include?(TeacherRelationable) && defined?(record.teacher)

      record.update_attribute(association.foreign_key, @main_teacher.id)
      return if association.name != :teacher_discipline_classrooms

      record.update_attribute(:teacher_api_code, @main_teacher.api_code)
    rescue ActiveRecord::RecordNotUnique
      raise unless association.name == :teacher_discipline_classrooms
      raise unless duplicate_allocation_kept_on_main?(record)

      discard(record)
    end

    def duplicate_allocation_kept_on_main?(record)
      keeper = TeacherDisciplineClassroom.unscoped.find_by(
        api_code: record.api_code,
        year: record.year,
        discipline_id: record.discipline_id,
        grade_id: record.grade_id,
        classroom_id: record.classroom_id,
        teacher_id: @main_teacher.id
      )
      return false if keeper.blank? || keeper.id == record.id

      LessonsBoardLessonWeekday.unscoped.where(teacher_discipline_classroom_id: record.id).update_all(
        teacher_discipline_classroom_id: keeper.id
      )
      true
    end

    def user_link_taken?(record)
      User.where(teacher_id: @main_teacher.id).where.not(id: record.id).exists?
    end

    def discard(record)
      return unless record.has_attribute?(:discarded_at)

      record.update_column(:discarded_at, Time.current)
    end
  end
end
