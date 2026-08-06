class AttendanceRecordReportByStudentPdf < BaseReport
  def self.build(entity_configuration, unity, range_dates, school_calendar_year, students_by_classrooms)
    new.build(entity_configuration, unity, range_dates, school_calendar_year, students_by_classrooms)
  end

  def build(entity_configuration, unity, range_dates, school_calendar_year, students_by_classrooms)
    @entity_configuration = entity_configuration
    @unity = unity
    @range_dates = range_dates
    @school_calendar_year = school_calendar_year
    @students_by_classrooms = students_by_classrooms || {}

    header
    body
    footer

    self
  end

  private

  def header
    title_cell = make_cell(
      content: 'Registro de Frequência por aluno',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 2
    )

    begin
      logo_cell = make_cell(
        image: open(@entity_configuration.logo.url),
        fit: [50, 50],
        width: 70,
        rowspan: 4,
        position: :center,
        vposition: :center
      )
    rescue StandardError
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration&.entity_name || ''
    organ_name = @entity_configuration&.organ_name || ''

    entity_organ_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 4,
      padding: [6, 0, 8, 0]
    )

    page_header do
      table([[title_cell], [logo_cell, entity_organ_cell]], width: bounds.width) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def identification
    identification_header = make_cell(
      content: 'Identificação',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 2
    )

    unity_header = make_cell(
      content: 'Unidade',
      size: 8,
      font_style: :bold,
      borders: [:left, :right, :top],
      padding: [2, 2, 4, 4],
      colspan: 2
    )
    unity_cell = make_cell(
      content: @unity&.name.to_s,
      size: 10,
      borders: [:left, :right, :bottom],
      padding: [0, 2, 4, 4],
      colspan: 2
    )

    period_header = make_cell(
      content: 'Período',
      size: 8,
      font_style: :bold,
      borders: [:left, :right, :top],
      padding: [2, 2, 4, 4]
    )
    year_header = make_cell(
      content: 'Ano letivo',
      size: 8,
      font_style: :bold,
      borders: [:left, :right, :top],
      padding: [2, 2, 4, 4]
    )
    period_cell = make_cell(
      content: @range_dates.to_s,
      size: 10,
      borders: [:left, :right, :bottom],
      padding: [0, 2, 4, 4]
    )
    year_cell = make_cell(
      content: @school_calendar_year.to_s,
      size: 10,
      borders: [:left, :right, :bottom],
      padding: [0, 2, 4, 4]
    )

    table(
      [
        [identification_header],
        [unity_header],
        [unity_cell],
        [period_header, year_header],
        [period_cell, year_cell]
      ],
      width: bounds.width
    ) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def body
    page_content do
      identification

      @students_by_classrooms.each_value do |classroom_info|
        move_down GAP
        render_classroom_table(classroom_info)
      end
    end
  end

  def render_classroom_table(classroom_info)
    grade_header = make_cell(
      content: "Série: #{classroom_info[:grade_name]}",
      size: 10,
      font_style: :bold,
      background_color: 'DEDEDE',
      align: :center,
      colspan: 3
    )
    classroom_header = make_cell(
      content: "Turma: #{classroom_info[:classroom_name]}",
      size: 10,
      font_style: :bold,
      background_color: 'DEDEDE',
      align: :center,
      colspan: 3
    )

    table_data = [
      [grade_header],
      [classroom_header],
      [
        make_cell(content: 'Nº', size: 8, font_style: :bold, align: :center),
        make_cell(content: 'Nome do aluno', size: 8, font_style: :bold),
        make_cell(content: 'Frequência', size: 8, font_style: :bold, align: :center)
      ]
    ]

    sequence = 0
    classroom_info[:students].each do |student|
      sequence += 1 unless student[:sequence]
      student_number = student[:sequence] || sequence
      frequency = student.dig(:frequency, :percentage_frequency)
      frequency_text = frequency.nil? ? '-' : "#{frequency}%"

      table_data << [
        make_cell(content: student_number.to_s, size: 9, align: :center),
        make_cell(content: student[:student_name].to_s, size: 9),
        make_cell(content: frequency_text, size: 9, align: :center)
      ]
    end

    table(table_data, width: bounds.width, header: true, column_widths: { 0 => 40, 2 => 80 }) do
      cells.border_width = 0.25
      cells.valign = :center
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end
end
