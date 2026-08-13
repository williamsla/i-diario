class AttendanceRecordReportPortrait < BaseReport
  NULL_FREQUENCY_STUDENT = NullDailyFrequencyStudent.new
  ACTIVE_SEARCH_FREQUENCY_STUDENT = ActiveSearchFrequencyStudent.new

  # This number represent how many students are printed on each page
  STUDENT_BY_PAGE_COUNT = 31

  # This factor represent the quantitty of students with social name needed to reduce 1 student by page
  SOCIAL_NAME_REDUCTION_FACTOR = 2

  NUMBER_OF_COLS = 25

  def self.build(
    entity_configuration,
    unity,
    teacher,
    year,
    start_at,
    end_at,
    daily_frequencies,
    enrollment_classrooms_list,
    events,
    school_calendar,
    second_teacher_signature,
    students_frequencies_percentage,
    current_user,
    classroom_description
  )
    new(:portrait)
      .build(entity_configuration,
             unity,
             teacher,
             year,
             start_at,
             end_at,
             daily_frequencies,
             enrollment_classrooms_list,
             events,
             school_calendar,
             second_teacher_signature,
             students_frequencies_percentage,
             current_user,
             classroom_description)

  end

  def build(
    entity_configuration,
    unity,
    teacher,
    year,
    start_at,
    end_at,
    daily_frequencies,
    enrollment_classrooms_list,
    events,
    school_calendar,
    second_teacher_signature,
    students_frequencies_percentage,
    current_user,
    classroom_description
  )

    @entity_configuration = entity_configuration
    @unity = unity
    @teacher = teacher
    @year = year
    @start_at = start_at
    @end_at = end_at
    @daily_frequencies = daily_frequencies
    @enrollment_classrooms = enrollment_classrooms_list
    @events = events
    @school_calendar = school_calendar
    @second_teacher_signature = ActiveRecord::Type::Boolean.new.cast(second_teacher_signature)
    @show_legend_hybrid = false
    @show_legend_remote = false
    @exists_legend_hybrid = false
    @exists_legend_remote = false
    @students_frequency_percentage = students_frequencies_percentage
    @classroom_description = classroom_description

    self.legend = 'Legenda: N - Não enturmado, D - Dispensado da disciplina, FJ - Falta justificada'

    @general_configuration = GeneralConfiguration.current
    @presence_mark = TermsDictionary.cached_current.try(:presence_identifier_character) || '.'
    @show_percentage_on_attendance = @general_configuration.show_percentage_on_attendance_record_report
    @show_inactive_enrollments = @general_configuration.show_inactive_enrollments
    @do_not_send_justified_absence = @general_configuration.do_not_send_justified_absence

    header
    content
    footer

    self
  end

  protected

  attr_accessor :any_student_with_dependence, :legend, :extra_school_event_description

  private

  def header
    attendance_header = make_cell(content: 'Registro de frequência', size: 12, font_style: :bold, background_color: 'DEDEDE', height: 20, padding: [2, 2, 4, 4], align: :center, colspan: 6)
    begin
      logo_cell = make_cell(image: entity_logo_io, fit: [50, 50], width: 70, rowspan: 4, position: :center, vposition: :center)
    rescue StandardError
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''

    entity_organ_and_unity_cell = make_cell(content: "#{entity_name}\n#{organ_name}\n#{@unity.name}", size: 10, leading: 1.5, align: :center, valign: :center, rowspan: 4, width:300, padding: [6, 0, 8, 0])
    classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 3)
    year_header = make_cell(content: 'Ano letivo', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan:1)
    teacher_header = make_cell(content: 'Professor(a)', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 4)
    classroom_cell = make_cell(content: @classroom_description, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 3)
    year_cell = make_cell(content: @year.to_s, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan:1)
    teacher_cell = make_cell(content: @teacher.name, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 4)

    discipline_header = make_cell(content: 'Disciplina', size: 8, font_style: :bold, colspan: 1, borders: [:top, :bottom, :left], padding: [2, 2, 4, 4])
    discipline_cell = make_cell(content: discipline_display, size: 10, colspan: 5, borders: [:top, :bottom, :right], padding: [0, 2, 4, 4])
    period_header = make_cell(content: 'Período', size: 8, colspan:1, font_style: :bold, borders: [:top, :bottom, :left], padding: [2, 2, 4, 4])
    period_cell = make_cell(content: "De #{@start_at} a #{@end_at}", size: 10, colspan: 5, borders: [:bottom, :right], padding: [0, 2, 4, 4])
    
    first_table_data = [[attendance_header],
                        [logo_cell, entity_organ_and_unity_cell, classroom_header, year_header],
                        [classroom_cell, year_cell],
                        [teacher_header],
                        [teacher_cell],
                        [discipline_header, discipline_cell],
                        [period_header, period_cell]]

    page_header do
      table(first_table_data, width: bounds.width, header: true) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def daily_frequencies_table
    self.any_student_with_dependence = false

    @daily_frequency_students = begin
      frequency_ids = @daily_frequencies.map(&:id)
      frequency_ids.empty? ? [] : DailyFrequencyStudent.by_daily_frequency_id(frequency_ids).to_a
    end
    frequency_students_index = build_frequency_students_index
    frequency_ids_with_students = @daily_frequency_students.each_with_object(Set.new) do |student_frequency, set|
      set << student_frequency.daily_frequency_id
    end

    daily_frequencies = @daily_frequencies.select { |daily_frequency| frequency_ids_with_students.include?(daily_frequency.id) }
    frequencies_and_events = daily_frequencies.to_a

    frequencies_and_events = frequencies_and_events.sort_by do |obj|
      daily_frequency?(obj) ? obj.frequency_date : obj[:date]
    end

    student_enrollment_ids = @enrollment_classrooms.map { |student_enrollment|
      student_enrollment[:student_enrollment].id
    }

    active_searches_index = active_searches_index_by_date(daily_frequencies, student_enrollment_ids)
    enrollments_meta = build_enrollments_meta

    sliced_frequencies_and_events = frequencies_and_events.each_slice(NUMBER_OF_COLS).to_a

    sliced_frequencies_and_events.each_with_index do |frequencies_and_events_slice, index|
      class_numbers = []
      days = []
      months = []
      students = {}

      frequencies_and_events_slice.each do |daily_frequency_or_event|
        if daily_frequency?(daily_frequency_or_event)
          daily_frequency = daily_frequency_or_event
          frequency_date = daily_frequency.frequency_date.to_date

          class_numbers << daily_frequency.class_number.to_s
          days << frequency_date.day.to_s
          months << frequency_date.month.to_s
          students_by_id = frequency_students_index[daily_frequency.id] || {}
          active_search_ids = active_searches_index[daily_frequency.frequency_date]

          enrollments_meta.each do |enrollment|
            student_id = enrollment[:student_id]
            enrollment_classroom_id = enrollment[:id]

            student_frequency = if active_search_ids&.include?(student_id)
                                  @show_legend_active_search = true
                                  ACTIVE_SEARCH_FREQUENCY_STUDENT
                                elsif @show_inactive_enrollments
                                  if frequency_date >= enrollment[:joined_at] && frequency_date < enrollment[:left_at]
                                    students_by_id[student_id]
                                  else
                                    NULL_FREQUENCY_STUDENT
                                  end
                                else
                                  students_by_id[student_id] || NULL_FREQUENCY_STUDENT
                                end

            if @show_legend_active_search && !@exists_active_search
              @exists_active_search = true
              self.legend += ', B - Busca ativa'
            end

            student_row = (students[enrollment_classroom_id] ||= {
              name: enrollment[:name],
              dependence: nil,
              absences: 0,
              sequence: @show_inactive_enrollments ? enrollment[:sequence] : nil,
              social_name: enrollment[:social_name],
              attendances: []
            })

            self.any_student_with_dependence ||= student_row[:dependence]

            if @show_percentage_on_attendance
              student_row[:absences_percentage] = @students_frequency_percentage[enrollment[:student_enrollment_id]]
            end

            unless student_frequency.present?
              absences = student_frequency.nil? ? 0 : 1
              if @do_not_send_justified_absence && student_frequency&.absence_justification_student_id
                absences = 0
              end

              student_row[:absences] += absences
            end

            student_row[:attendances] << attendance_mark(student_frequency)
          end
        else # Se não for dia letivo
          school_calendar_event = daily_frequency_or_event
          legend = ', ' + school_calendar_event[:legend].to_s + ' - ' + school_calendar_event[:description]
          self.legend += legend unless self.legend.include?(legend)

          class_numbers << ''
          days << school_calendar_event[:date].day.to_s
          months << school_calendar_event[:date].month.to_s

          enrollments_meta.each do |enrollment|
            student_row = (students[enrollment[:id]] ||= {
              name: enrollment[:name],
              dependence: nil,
              absences: 0,
              sequence: @show_inactive_enrollments ? enrollment[:sequence] : nil,
              social_name: enrollment[:social_name],
              attendances: []
            })

            if @show_percentage_on_attendance
              student_row[:absences_percentage] = @students_frequency_percentage[enrollment[:student_enrollment_id]]
            end

            student_row[:attendances] << school_calendar_event[:legend].to_s
          end
        end
      end

      bottom_offset = @second_teacher_signature ? 24 : 0
      student_list = []
      sequence = 1 unless @show_inactive_enrollments
      sequence_reseted = false

      students.sort_by { |(_key, value)| value[:dependence] ? 1 : 0 }.each do |_key, value|
        if !sequence_reseted && value[:dependence]
          sequence = 1
          sequence_reseted = true
        end

        student_list << value.merge(
          sequence: @show_inactive_enrollments ? value[:sequence] : sequence,
          display_name: (value[:dependence] ? '* ' : '') + value[:name].to_s
        )
        sequence += 1 unless @show_inactive_enrollments
      end

      sliced_students = student_list.each_slice(student_slice_size(students)).to_a

      sliced_students.each_with_index do |students_slice, slice_index|
        aulas_dadas = if slice_index == sliced_students.count - 1 && index == sliced_frequencies_and_events.count - 1
                        daily_frequencies.count
                      end

        page_content do
          draw_frequency_grid(class_numbers, days, months, students_slice, aulas_dadas)
        end

        text_box(self.legend, size: 8, at: [0, 30 + bottom_offset], width: 585, height: 20)

        start_new_page if slice_index < sliced_students.count - 1
      end

      text_box(self.legend, size: 8, at: [0, 30 + bottom_offset], width: 585, height: 20)

      self.legend = 'Legenda: N - Não enturmado, D - Dispensado da disciplina, FJ - Falta justificada'

      if index < sliced_frequencies_and_events.count - 1
        start_new_page
      elsif show_school_day_event_description?
        events = format_legend(extra_school_events)
        height = 20
        at = [0, 50 + bottom_offset]

        if events.size > 485
          height = bounds.height
          at = [0, height]
          start_new_page
        end

        text_box_overflow_to_new_page(events, 8, at, 585, height)
      end
    end
  end

  def draw_frequency_grid(class_numbers, days, months, student_rows, aulas_dadas)
    width = bounds.width
    num_w = 18.0
    abs_w = 28.0
    freq_w = @show_percentage_on_attendance ? 26.0 : 0.0
    att_count = NUMBER_OF_COLS
    att_w = 13.0
    name_w = width - num_w - (att_count * att_w) - abs_w - freq_w
    row_h = 11.0
    header_h = 11.0
    extra_h = aulas_dadas ? row_h : 0
    total_h = (3 * header_h) + (student_rows.size * row_h) + extra_h
    start_y = cursor
    bottom = start_y - total_h
    x_att = num_w + name_w
    x_abs = x_att + (att_count * att_w)
    x_freq = x_abs + abs_w

    pad = ->(values) { values + Array.new([att_count - values.size, 0].max, '') }

    line_width 0.25
    stroke_color '000000'
    fill_color '000000'

    student_rows.each_with_index do |_row, index|
      next if index.even?

      y_bottom = start_y - (3 * header_h) - ((index + 1) * row_h)
      fill_color 'DEDEDE'
      fill_rectangle [0, y_bottom], width, row_h
    end
    fill_color '000000'

    header_mid_y = start_y - (2 * header_h) + 3
    draw_text 'Nº', size: 8, style: :bold, at: [3, header_mid_y]
    draw_text 'Nome do aluno', size: 8, style: :bold, at: [num_w + 4, header_mid_y]
    draw_text 'Aula', size: 7, style: :bold, at: [x_att - 22, start_y - header_h + 3]
    draw_text 'Dia', size: 7, style: :bold, at: [x_att - 18, start_y - (2 * header_h) + 3]
    draw_text 'Mês', size: 7, style: :bold, at: [x_att - 18, start_y - (3 * header_h) + 3]
    draw_text 'Faltas', size: 7, style: :bold, at: [x_abs + 2, header_mid_y]
    draw_text 'Freq.', size: 7, style: :bold, at: [x_freq + 2, header_mid_y] if @show_percentage_on_attendance

    pad.call(class_numbers).each_with_index do |value, index|
      draw_centered_mark(value, x_att + (index * att_w), start_y - header_h, att_w)
    end
    pad.call(days).each_with_index do |value, index|
      draw_centered_mark(value, x_att + (index * att_w), start_y - (2 * header_h), att_w)
    end
    pad.call(months).each_with_index do |value, index|
      draw_centered_mark(value, x_att + (index * att_w), start_y - (3 * header_h), att_w)
    end

    student_rows.each_with_index do |row, index|
      y_bottom = start_y - (3 * header_h) - ((index + 1) * row_h)
      name = row[:display_name].to_s
      name = "#{name[0, 40]}..." if name.length > 42

      draw_text row[:sequence].to_s, size: 8, at: [4, y_bottom + 3]
      draw_text name, size: 8, at: [num_w + 2, y_bottom + 3]
      Array(row[:attendances]).each_with_index do |mark, mark_index|
        break if mark_index >= att_count

        draw_centered_mark(mark, x_att + (mark_index * att_w), y_bottom, att_w)
      end
      draw_text row[:absences].to_s, size: 8, at: [x_abs + 8, y_bottom + 3]
      next unless @show_percentage_on_attendance

      draw_text (row[:absences_percentage] || '100%').to_s, size: 7, at: [x_freq + 1, y_bottom + 3]
    end

    if aulas_dadas
      draw_text "Aulas dadas: #{aulas_dadas}", size: 8, at: [(width / 2) - 40, bottom + 3]
    end

    stroke_rectangle [0, bottom], width, total_h
    3.times do |index|
      y = start_y - ((index + 1) * header_h)
      if index < 2
        stroke_horizontal_line x_att, width, at: y
      else
        stroke_horizontal_line 0, width, at: y
      end
    end
    student_rows.size.times do |index|
      stroke_horizontal_line 0, width, at: start_y - (3 * header_h) - ((index + 1) * row_h)
    end

    stroke_vertical_line start_y, bottom, at: num_w
    stroke_vertical_line start_y, bottom, at: x_att
    att_count.times do |index|
      stroke_vertical_line start_y, bottom, at: x_att + ((index + 1) * att_w)
    end
    stroke_vertical_line start_y, bottom, at: x_abs
    stroke_vertical_line start_y, bottom, at: x_freq if @show_percentage_on_attendance

    move_cursor_to bottom
  end

  def draw_centered_mark(text, x, y_bottom, col_width)
    value = text.to_s
    return if value.empty?

    offset = value.length <= 1 ? (col_width / 2) - 2 : (col_width / 2) - 5
    draw_text value, size: 7, at: [x + offset, y_bottom + 3]
  end

  def content
    daily_frequencies_table
  end

  def footer
    page_footer do
      repeat(:all) do
        # if @second_teacher_signature
          # draw_text('Assinatura do(a) professor(a):', size: 8, style: :bold, at: [0, 24])
          # draw_text('________________________________________', size: 8, at: [117, 24])
        # end

        draw_text('Assinatura do(a) professor(a):', size: 8, style: :bold, at: [0, 0])
        draw_text('________________________________________', size: 8, at: [0, 14])

        draw_text('Assinatura do(a) coordenador(a):', size: 8, style: :bold, at: [300, 0])
        draw_text('________________________________________', size: 8, at: [300, 14])

        if any_student_with_dependence
          offset = @second_teacher_signature ? 24 : 0
          draw_text('* Alunos cursando dependência', size: 8, at: [0, 47 + offset])
        end
      end
    end
  end

  def get_left_at(left_at)
    left_at.empty? ? Date.current.end_of_year : left_at.to_date
  end

  def event?(record)
    record.class.to_s == 'SchoolCalendarEvent'
  end

  def daily_frequency?(record)
    record.is_a? DailyFrequency
  end

  def student_has_dependence?(all_dependances, student_enrollment, daily_frequency)
    all_dependances.detect do |dependency|
      dependency.student_enrollment_id.eql?(student_enrollment.id) &&
        dependency.discipline_id.eql?(daily_frequency.discipline_id)
    end
  end

  def exempted_from_discipline?(all_exempts, student_enrollment, daily_frequency)
    return false if daily_frequency.discipline_id.blank?

    step_number = step_number(daily_frequency)
    discipline_id = daily_frequency.discipline_id

    exemption = all_exempts.detect { |exempt|
                  exempt.student_enrollment_id.eql?(student_enrollment.id) &&
                    exempt.discipline_id.eql?(discipline_id) &&
                    exempt.steps.split(',').include?(step_number.to_s)
                }

    exemption.present?
  end

  def student_slice_size(students)
    student_with_social_name_count = students.select { |(_key, value)|
      value[:social_name].present?
    }.length

    second_signature_offset = @second_teacher_signature ? 3 : 0
    social_name_factor = (student_with_social_name_count / SOCIAL_NAME_REDUCTION_FACTOR)

    slice_size = STUDENT_BY_PAGE_COUNT - second_signature_offset - social_name_factor

    return slice_size unless show_school_day_event_description?

    slice_size - 3
  end

  def step_number(daily_frequency)
    @steps ||= StepsFetcher.new(daily_frequency.classroom).steps

    step = @steps.detect { |step|
      step[:start_at] <= daily_frequency.frequency_date && step[:end_at] >= daily_frequency.frequency_date
    }

    step&.to_number
  end

  def frequency_in_period(daily_frequency)
    step_number(daily_frequency).present?
  end

  def discipline_display
    return 'Geral' if general_frequency?

    discipline.to_s
  end

  def classroom_has_general_absence?
    classroom.first_exam_rule.frequency_type == FrequencyTypes::GENERAL
  end

  def teacher_allow_absence_by_discipline?
    @teacher_allow_absence_by_discipline ||= TeacherDisciplineClassroom.by_classroom(classroom.id)
                                                                       .by_teacher_id(@teacher.id)
                                                                       .by_discipline_id(discipline.id)
                                                                       .first
                                                                       .try(:allow_absence_by_discipline)
  end

  def active_searches_index_by_date(daily_frequencies, student_enrollment_ids)
    dates = daily_frequencies.map(&:frequency_date).uniq
    result = {}

    ActiveSearch.new.in_active_search_in_range(student_enrollment_ids, dates).each do |entry|
      next if entry.blank? || entry[:student_ids].blank?

      result[entry[:date]] = entry[:student_ids].to_set
    end

    result
  end

  def build_enrollments_meta
    @enrollment_classrooms.map do |enrollment_classroom|
      student_enrollment_classroom = enrollment_classroom[:student_enrollment_classroom]
      student = enrollment_classroom[:student]

      {
        id: student_enrollment_classroom.id,
        student_id: student.id,
        name: student.to_s,
        social_name: student.social_name,
        student_enrollment_id: enrollment_classroom[:student_enrollment].id,
        joined_at: student_enrollment_classroom.joined_at.to_date,
        left_at: get_left_at(student_enrollment_classroom.left_at),
        sequence: student_enrollment_classroom.sequence
      }
    end
  end

  def attendance_mark(student_frequency)
    return '' if student_frequency.nil?
    return student_frequency.to_s unless student_frequency.respond_to?(:absence_justification_student_id)

    if student_frequency.absence_justification_student_id
      'FJ'
    elsif student_frequency.present?
      @presence_mark
    else
      'F'
    end
  end

  def general_frequency?
    discipline.blank?
  end

  def knowledge_area
    @knowledge_area ||= discipline.knowledge_area
  end

  def discipline
    @discipline ||= @daily_frequencies.first.discipline
  end

  def classroom
    @classroom ||= @daily_frequencies.first.classroom
  end

  def extra_school_events
    @extra_school_events ||= @school_calendar.events.select { |event|
      event.event_type == EventTypes::EXTRA_SCHOOL &&
        event.show_in_frequency_record &&
        report_include_event_date?(event)
    }
  end

  def show_school_day_event_description?
    return false if extra_school_events.empty?

    true
  end

  def report_include_event_date?(event)
    event.start_date <= @end_at.to_date && event.end_date >= @start_at.to_date
  end

  def format_legend(events)
    all_events = []

    events.each do |event|
      event_date = if event.start_date == event.end_date
                     event.start_date.strftime('%d/%m/%Y').to_s
                   else
                     "#{event.start_date.strftime('%d/%m/%Y')} à #{event.end_date.strftime('%d/%m/%Y')}"
                   end

      all_events << "#{event.description}: #{event_date}"
    end

    all_events.join(', ')
  end

  def build_frequency_students_index
    index = {}

    @daily_frequency_students.each do |student_frequency|
      next unless student_frequency.active.eql?(true)

      (index[student_frequency.daily_frequency_id] ||= {})[student_frequency.student_id] = student_frequency
    end

    index
  end

  def frequency_hybrid_or_remote(student_enrollment, daily_frequency)
    student_frequency = @daily_frequency_students.detect { |student_frequency|
      student_frequency.student_id.eql?(student_enrollment.student_id)
    }

    return if student_frequency.blank?
    return if student_frequency.type_of_teaching == TypesOfTeaching::PRESENTIAL

    if student_frequency.type_of_teaching == TypesOfTeaching::HYBRID
      @show_legend_hybrid = true
      'S'
    else
      @show_legend_remote = true
      'R'
    end
  end

  def is_school_day?(date)
    return true if @events.empty?

    @events.detect { |event| event[:date].eql?(date) && event[:type].eql?(EventTypes::NO_SCHOOL) }.blank?
  end

end
