class LessonsBoard < ActiveRecord::Base
  include Audit
  include Discardable
  include Filterable

  audited

  validates :period, :classrooms_grade_id, presence: true

  belongs_to :classrooms_grade
  has_many :lessons_board_lessons

  attr_accessor :unity, :grade, :lessons_number, :classroom_id

  accepts_nested_attributes_for :lessons_board_lessons, allow_destroy: true

  delegate :classroom, :classroom_id, :grade_id, to: :classrooms_grade, allow_nil: true
  delegate :unity_id, to: :classroom, allow_nil: true

  default_scope -> { kept }

  scope :by_year, ->(year) { joins(classrooms_grade: :classroom).where(classrooms: { year: year }) }
  scope :by_unity, ->(unity) { joins(classrooms_grade: :classroom).where(classrooms: { unity_id: unity }) }
  scope :by_grade, ->(grade) { joins(classrooms_grade: :classroom).merge(ClassroomsGrade.by_grade_id(grade)) }
  scope :by_classroom, ->(classroom) { joins(:classrooms_grade).where(classrooms_grades: { classroom_id: classroom }) }
  scope :by_period, ->(period) { where(lessons_boards: { period: period }) }
  scope :by_teacher, ->(teacher_id) do
    joins(lessons_board_lessons: [lessons_board_lesson_weekdays: [:teacher_discipline_classroom]])
      .where(teacher_discipline_classrooms: { teacher_id: teacher_id })
  end
  scope :by_discipline, ->(discipline_id) do
    joins(lessons_board_lessons: [lessons_board_lesson_weekdays: [:teacher_discipline_classroom]])
      .where(teacher_discipline_classrooms: { discipline_id: discipline_id })
  end
  scope :ordered, -> { order(created_at: :desc) }

  after_discard do
    lessons_board_lessons.discard_all
  end

  after_undiscard do
    lessons_board_lessons.with_discarded.undiscard_all
  end

  # date <= arquivado até => quadro daquela vigência; depois disso => quadro ativo.
  # discarded_at é end_of_day em Brasília (no UTC cai no dia seguinte).
  def self.ids_covering_date(classroom_id, date)
    boards_covering_date(classroom_id, date).map(&:id)
  end

  def self.boards_covering_date(classroom_id, date)
    return [] if classroom_id.blank? || date.blank?

    date = date.to_date
    effective_for_classroom(classroom_id)
      .group_by { |board| [board.classrooms_grade_id, board.period] }
      .flat_map { |_key, boards| boards_in_effect_on(boards, date) }
  end

  def self.effective_for_classroom(classroom_id)
    boards = unscoped
             .joins(:classrooms_grade)
             .where(classrooms_grades: { classroom_id: classroom_id })
             .to_a

    calendar_start = calendar_start_for_classroom(classroom_id)
    boards.reject { |board| purged_before_calendar?(board, calendar_start) }
  end

  def self.allocations_on_date(classroom_id:, date:, weekday:, discipline_id: nil, teacher_id: nil, period: nil)
    return [] if weekday.blank?

    scope = weekday_scope_for_boards(classroom_id, ids_covering_date(classroom_id, date))
    return [] if scope.nil?

    scope = scope.where(weekday: weekday)
    scope = scope.where(teacher_discipline_classrooms: { discipline_id: discipline_id }) if discipline_id.present?
    scope = scope.where(teacher_discipline_classrooms: { teacher_id: teacher_id }) if teacher_id.present?
    scope = scope.where(lessons_boards: { period: period }) if period.present?

    attach_board_graph(scope.distinct.to_a)
  end

  def self.discipline_ids_on_boards(classroom_id, board_ids)
    scope = weekday_scope_for_boards(classroom_id, board_ids)
    return [] if scope.nil?

    scope.distinct.pluck('teacher_discipline_classrooms.discipline_id')
  end

  def self.discarded_at_as_local_date(discarded_at)
    return if discarded_at.blank?

    discarded_at.in_time_zone.to_date
  end

  def self.boards_in_effect_on(boards, date)
    archived = boards.select { |board| board.discarded_at.present? }.sort_by(&:discarded_at)
    active = boards.select { |board| board.discarded_at.blank? }
    return active if archived.empty?

    window_start = nil
    archived.each do |board|
      archive_date = discarded_at_as_local_date(board.discarded_at)
      next if archive_date.blank?

      if (window_start.nil? || date > window_start) && date <= archive_date
        return archived.select { |candidate| discarded_at_as_local_date(candidate.discarded_at) == archive_date }
      end

      window_start = archive_date
    end

    return active if window_start && date > window_start

    []
  end
  private_class_method :boards_in_effect_on

  def self.weekday_scope_for_boards(classroom_id, board_ids)
    return nil if classroom_id.blank? || board_ids.blank?

    LessonsBoardLessonWeekday.unscoped
                             .joins(weekday_board_joins_sql)
                             .where(lessons_boards: { id: board_ids })
                             .where(teacher_discipline_classrooms: {
                               classroom_id: classroom_id,
                               active: true,
                               discarded_at: nil
                             })
                             .where(kept_or_archived_with_board_sql)
  end
  private_class_method :weekday_scope_for_boards

  def self.weekday_board_joins_sql
    <<-SQL.squish
      INNER JOIN lessons_board_lessons
        ON lessons_board_lessons.id = lessons_board_lesson_weekdays.lessons_board_lesson_id
      INNER JOIN lessons_boards
        ON lessons_boards.id = lessons_board_lessons.lessons_board_id
      INNER JOIN teacher_discipline_classrooms
        ON teacher_discipline_classrooms.id = lessons_board_lesson_weekdays.teacher_discipline_classroom_id
    SQL
  end
  private_class_method :weekday_board_joins_sql

  def self.kept_or_archived_with_board_sql
    <<-SQL.squish
      (
        (
          lessons_boards.discarded_at IS NULL
          AND lessons_board_lessons.discarded_at IS NULL
          AND lessons_board_lesson_weekdays.discarded_at IS NULL
        )
        OR lessons_boards.discarded_at IS NOT NULL
      )
    SQL
  end
  private_class_method :kept_or_archived_with_board_sql

  def self.attach_board_graph(weekdays)
    return weekdays if weekdays.blank?

    lessons = LessonsBoardLesson.unscoped.where(id: weekdays.map(&:lessons_board_lesson_id).uniq).to_a
    boards = unscoped.where(id: lessons.map(&:lessons_board_id).uniq).index_by(&:id)
    lessons_by_id = lessons.index_by(&:id)

    lessons.each do |lesson|
      board_association = lesson.association(:lessons_board)
      board_association.target = boards[lesson.lessons_board_id]
      board_association.loaded!
    end

    weekdays.each do |weekday|
      lesson_association = weekday.association(:lessons_board_lesson)
      lesson_association.target = lessons_by_id[weekday.lessons_board_lesson_id]
      lesson_association.loaded!
    end

    weekdays.sort_by { |weekday| weekday.lessons_board_lesson&.lesson_number.to_i }
  end
  private_class_method :attach_board_graph

  def self.purged_before_calendar?(board, calendar_start)
    board.discarded_at.present? && calendar_start.present? && board.discarded_at < calendar_start
  end
  private_class_method :purged_before_calendar?

  def self.calendar_start_for_classroom(classroom_id)
    classroom = Classroom.find_by(id: classroom_id)
    return if classroom.blank?

    calendar = CurrentSchoolCalendarFetcher.new(classroom.unity, classroom, classroom.year).fetch
    calendar&.first_day&.to_date&.beginning_of_day
  rescue StandardError
    nil
  end
  private_class_method :calendar_start_for_classroom
end
