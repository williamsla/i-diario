class ClassCouncilReport < BaseReport
  ROWS_PER_STUDENT = 5
  FONT_SIZE = 6
  HEADER_BG = 'DEDEDE'

  def self.build(entity_configuration, report_data)
    new(:landscape).build(entity_configuration, report_data)
  end

  def build(entity_configuration, report_data)
    @entity_configuration = entity_configuration
    @report_data = report_data
    @classroom = report_data[:classroom]
    @disciplines = report_data[:disciplines]
    @steps = report_data[:steps]
    @students = report_data[:students]

    header
    move_down 6
    content
    footer

    self
  end

  private

  def header
    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''
    unity_name = @classroom.unity.name

    title = make_cell(
      content: 'Conselho de Classe',
      size: 12,
      font_style: :bold,
      background_color: HEADER_BG,
      align: :center,
      colspan: 6,
      padding: [4, 4, 4, 4]
    )

    begin
      logo_cell = make_cell(
        image: open(@entity_configuration.logo.url),
        fit: [50, 50],
        width: 70,
        rowspan: 2,
        position: :center,
        vposition: :center
      )
    rescue StandardError
      logo_cell = make_cell(content: '', width: 70, rowspan: 2)
    end

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n#{unity_name}",
      size: 10,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 2,
      padding: [4, 4, 8, 4]
    )

    header_table_data = [
      [title],
      [
        logo_cell,
        entity_organ_and_unity_cell,
        make_cell(content: 'Curso', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Turno', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Série', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Turma', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
      ],
      [
        make_cell(content: @report_data[:course_name].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4]),
        make_cell(content: @report_data[:period_name].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4]),
        make_cell(content: @report_data[:grade_name].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4]),
        make_cell(content: @classroom.description.to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])
      ]
    ]

    table(header_table_data, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
      row(0).align = :center
    end

    move_down 4
  end

  def content
    table([column_headers] + student_rows, width: bounds.width, header: true) do
      cells.border_width = 0.25
      cells.size = FONT_SIZE
      row(0).font_style = :bold
      row(0).background_color = HEADER_BG
      row(0).align = :center
    end
  end

  def column_headers
    row = [
      make_cell(content: 'Ord.', size: FONT_SIZE, font_style: :bold, align: :center, width: 18),
      make_cell(content: 'Aluno', size: FONT_SIZE, font_style: :bold, align: :center, width: 95),
      make_cell(content: 'Sit.', size: FONT_SIZE, font_style: :bold, align: :center, width: 18),
      make_cell(content: 'Freq. - Falta', size: FONT_SIZE, font_style: :bold, align: :center, width: 52)
    ]

    @disciplines.each do |discipline|
      row << make_cell(content: discipline[:abbreviation], size: FONT_SIZE, font_style: :bold, align: :center, colspan: 2)
    end

    row
  end

  def student_rows
    rows = []

    @students.each do |student|
      rows.concat(student_block_rows(student))
    end

    rows
  end

  def student_block_rows(student)
    first_row = [
      make_cell(content: student[:order].to_s, rowspan: ROWS_PER_STUDENT, align: :center, valign: :center, width: 18),
      make_cell(content: student[:name].to_s.upcase, rowspan: ROWS_PER_STUDENT, align: :left, valign: :center, width: 95),
      make_cell(content: student[:situation].to_s, rowspan: ROWS_PER_STUDENT, align: :center, valign: :center, width: 18),
      make_cell(
        content: format_frequency(student[:frequency_percentage], student[:total_absences]),
        align: :center,
        width: 52
      )
    ]

    @disciplines.each do |_discipline|
      first_row << make_cell(content: 'Notas', align: :center, width: 20)
      first_row << make_cell(content: 'F', align: :center, width: 12)
    end

    step_rows = student[:steps].first(ROWS_PER_STUDENT - 1).map do |step|
      row = [
        make_cell(content: step[:label], align: :center, width: 52)
      ]

      step[:disciplines].each do |discipline_data|
        row << make_cell(content: format_score(discipline_data[:score]), align: :center, width: 20)
        row << make_cell(content: discipline_data[:absences].to_s, align: :center, width: 12)
      end

      row
    end

    while step_rows.size < (ROWS_PER_STUDENT - 1)
      step_rows << empty_step_row
    end

    [first_row] + step_rows
  end

  def empty_step_row
    row = [make_cell(content: '', width: 52)]

    @disciplines.each do |_discipline|
      row << make_cell(content: '', width: 20)
      row << make_cell(content: '', width: 12)
    end

    row
  end

  def table_width_columns
    4 + (@disciplines.size * 2)
  end

  def format_frequency(percentage, absences)
    "#{format('%.2f', percentage)}% - #{absences}"
  end

  def format_score(score)
    return '' if score.blank?

    number_with_precision(score, precision: 1, separator: ',', delimiter: '.')
  end
end
