class StudentClassroomEnrollments
  def self.for_student(student_id, classroom_id)
    enrollments = StudentEnrollment.by_student(student_id)
                                   .by_classroom(classroom_id)
                                   .active
                                   .includes(:student, student_enrollment_classrooms: :classrooms_grade)
                                   .to_a

    ordered(enrollments, classroom_id)
  end

  def self.ordered(enrollments, classroom_id)
    enrollments.uniq(&:id).sort_by { |enrollment| recency(enrollment, classroom_id) }
  end

  def self.sequence_in_classroom(enrollment, classroom_id)
    latest_link(enrollment, classroom_id)&.sequence.to_i
  end

  def self.recency(enrollment, classroom_id)
    link = latest_link(enrollment, classroom_id)

    [
      link&.joined_at || Date.new(1, 1, 1),
      link&.index.to_i,
      enrollment.id.to_i
    ]
  end

  def self.latest_link(enrollment, classroom_id)
    enrollment.student_enrollment_classrooms
              .select { |link| link.classrooms_grade&.classroom_id == classroom_id }
              .max_by { |link| [link.joined_at || Date.new(1, 1, 1), link.index.to_i, link.id.to_i] }
  end
end
