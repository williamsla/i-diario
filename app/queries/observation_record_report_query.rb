class ObservationRecordReportQuery
  def initialize(unity_id, teacher_id, classroom_id, discipline_id, start_at, end_at, current_user_id, student_id = nil, observation_diary_record_id = nil)
    @unity_id = unity_id
    @teacher_id = teacher_id
    @classroom_id = classroom_id
    @discipline_id = discipline_id
    @start_at = start_at.to_date
    @end_at = end_at.to_date
    @current_user_id = current_user_id
    @student_id = student_id
    @observation_diary_record_id = observation_diary_record_id
  end

  def observation_diary_records
    if @classroom_id.eql?('all')
      user = User.find(current_user_id)
      @classroom_id = if user.teacher?
                        Classroom.by_unity_and_teacher(unity_id, user.teacher_id).pluck(:id)
                      else
                        Classroom.by_unity(unity_id).pluck(:id)
                      end
    end

    relation = ObservationDiaryRecord.includes(:classroom, :teacher, notes: :students)
                                     .by_classroom(classroom_id)
                                     .where(date: start_at..end_at)
                                     .order(:date)

    unless @discipline_id.blank? || @discipline_id.eql?('all')
      relation = relation.by_discipline(@discipline_id)
    end

    if @student_id.present? && !@student_id.eql?('all')
      relation = relation.by_student_id(@student_id).distinct
    end

    if @observation_diary_record_id.present?
      return relation.where(id: @observation_diary_record_id)
    end

    from_teachers_of_the_classroom(relation)
  end

  private

  attr_accessor :unity_id, :teacher_id, :classroom_id, :discipline_id, :start_at, :end_at,
                :current_user_id, :student_id, :observation_diary_record_id

  def from_teachers_of_the_classroom(relation)
    allocation_sql = TeacherDisciplineClassroom
      .where('teacher_discipline_classrooms.teacher_id = observation_diary_records.teacher_id')
      .where('teacher_discipline_classrooms.classroom_id = observation_diary_records.classroom_id')
      .select('1')
      .to_sql

    relation.where(
      "observation_diary_records.discipline_id IS NULL OR EXISTS (#{allocation_sql})"
    )
  end
end
