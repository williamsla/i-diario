class ObservationRecordReport < BaseReportOld
  def title
    t(:title)
  end

  def body
    page_content do
      identification
      general_information
      signatures
    end
  end

  def translation_scope
    'reports.observation_record_report'.freeze
  end

  private

  def identification
    identification_table_header_cell = make_table_header_cell(
      t(:identification_header),
      colspan: 2
    )

    unity_header = make_row_header_cell(t(:unity), colspan: 2)
    unity_cell = make_content_cell(@form.unity.to_s, colspan: 2)
    discipline_header = make_row_header_cell(t(:discipline), width: 70)
    classroom_header = make_row_header_cell(t(:classroom))

    discipline_name = if @form.discipline_id.blank? || @form.discipline_id.eql?('all')
                        'Todas'
                      elsif @form.discipline.present?
                        @form.discipline.to_s
                      else
                        t(:empty_discipline)
                      end

    classroom_name = if @form.classroom_id.blank? || @form.classroom_id.eql?('all')
                       'Todas'
                     else
                       @form.classroom.to_s
                     end

    discipline_cell = make_content_cell(discipline_name, width: 70)
    classroom_cell = make_content_cell(classroom_name)
    period_header = make_row_header_cell(t(:period), colspan: 2)
    period_cell = make_content_cell(
      t(:period_content, start_at: @form.start_at, end_at: @form.end_at),
      colspan: 2
    )

    table_data = [
      [identification_table_header_cell],
      [unity_header],
      [unity_cell],
      [discipline_header, classroom_header],
      [discipline_cell, classroom_cell],
      [period_header],
      [period_cell]
    ]

    if @form.student.present?
      student_header = make_row_header_cell(t(:student), colspan: 2)
      student_cell = make_content_cell(@form.student.to_s, colspan: 2)
      table_data << [student_header]
      table_data << [student_cell]
    end

    table(table_data, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def general_information
    general_information_header_cell = make_table_header_cell(
      t(:general_information),
      colspan: 5
    )

    title_general_information = [
      [general_information_header_cell]
    ]

    date_header = make_row_header_cell(t(:date), width: 62)
    students_header = make_row_header_cell(t(:students), width: 207)
    observations_header = make_row_header_cell(t(:observation))

    general_information_headers = [
      date_header,
      students_header,
      observations_header
    ]

    table(title_general_information, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    records_by_classroom.each do |classroom, classroom_records|
      classroom_header(classroom) if grouped_by_classroom?

      general_information_table_data = [general_information_headers]
      classroom_records.each do |record|
        record.notes.each do |note|
          next if @form.student.present? && note.students.map(&:id).exclude?(@form.student.id)

          students = if @form.student.present?
                       @form.student.to_s
                     else
                       note.students.map(&:to_s).join(', ')
                     end

          date_cell = make_row_cell(record.localized.date, width: 62)
          students_cell = make_row_cell(students, width: 207)
          observation_cell = make_row_cell(
            observation_content(record, note),
            inline_format: true
          )

          general_information_table_data << [
            date_cell,
            students_cell,
            observation_cell
          ]
        end
      end

      table(general_information_table_data, row_colors: [GRAY, WHITE], width: bounds.width, header: true) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end

      move_down GAP if grouped_by_classroom?
    end
  end

  def observation_content(record, note)
    text = note.description.to_s
    text = "#{t(:active_search)}: #{text}" if record.active_search?
    content = escape_inline(text)
    author = record.teacher&.to_s
    return content if author.blank?

    "#{content}\n<font size='8'><color rgb='777777'><i>#{escape_inline(t(:author, name: author))}</i></color></font>"
  end

  def escape_inline(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def grouped_by_classroom?
    @form.classroom_id.blank? || @form.classroom_id.to_s.eql?('all')
  end

  def records_by_classroom
    records = @form.observation_diary_records.to_a
    return [[nil, records]] unless grouped_by_classroom?

    records.group_by(&:classroom).sort_by { |classroom, _records| classroom.to_s }
  end

  def classroom_header(classroom)
    header_cell = make_table_header_cell(classroom.to_s, colspan: 3)

    table([[header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def signatures
    start_new_page if cursor < 45

    move_down 30

    text_box(t(:teacher_signature), size: 10, align: :center, at: [0, cursor], width: 260)
    text_box(t(:coordinator_signature), size: 10, align: :center, at: [306, cursor], width: 260)
  end
end
