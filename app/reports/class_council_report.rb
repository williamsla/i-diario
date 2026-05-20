class ClassCouncilReport < BaseReport
  ROWS_PER_STUDENT = 5
  FONT_SIZE = 6
  HEADER_BG = 'DEDEDE'
  BELOW_MINIMUM_COLOR = 'FF0000'
  BELOW_MINIMUM_BACKGROUND = 'FFE5E5'
  MIN_STUDENT_WIDTH = 55
  MIN_SCORE_WIDTH = 11
  MIN_ABSENCE_WIDTH = 8
  STUDENT_COLUMN_WIDTH_FACTOR = 0.9
  SCORE_COLUMN_WIDTH_FACTOR = 0.8
  ABSENCE_COLUMN_WIDTH_FACTOR = 0.7

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
      colspan: 7,
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
      padding: [4, 4, 8, 4],
      overflow: :shrink_to_fit,
      min_font_size: 6
    )

    header_table_data = [
      [title],
      [
        logo_cell,
        entity_organ_and_unity_cell,
        make_cell(content: 'Ano letivo', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Curso', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Turno', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Série', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4]),
        make_cell(content: 'Turma', size: 8, font_style: :bold, align: :center, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
      ],
      [
        make_cell(content: @report_data[:school_year].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], overflow: :shrink_to_fit, min_font_size: 6),
        make_cell(content: @report_data[:course_name].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], overflow: :shrink_to_fit, min_font_size: 6),
        make_cell(content: @report_data[:period_name].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], overflow: :shrink_to_fit, min_font_size: 6),
        make_cell(content: @report_data[:grade_name].to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], overflow: :shrink_to_fit, min_font_size: 6),
        make_cell(content: @classroom.description.to_s, size: 9, align: :center, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], overflow: :shrink_to_fit, min_font_size: 6)
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
    font_size = content_font_size

    table(
      [column_headers] + student_rows,
      width: bounds.width,
      column_widths: column_widths_array,
      header: true,
      cell_style: { overflow: :shrink_to_fit, min_font_size: 4, size: font_size }
    ) do
      cells.border_width = 0.25
      row(0).font_style = :bold
      row(0).background_color = HEADER_BG
      row(0).align = :center
    end
  end

  def column_headers
    row = [
      table_cell('Ord.', font_style: :bold, align: :center),
      table_cell('Aluno', font_style: :bold, align: :center),
      table_cell('Sit.', font_style: :bold, align: :center),
      table_cell('Freq. - Falta', font_style: :bold, align: :center)
    ]

    @disciplines.each do |discipline|
      row << table_cell(discipline[:abbreviation], font_style: :bold, align: :center, colspan: 2)
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
    student_below_minimum = student_below_minimum?(student)
    student_name = truncate_student_name(student[:name])

    first_row = [
      table_cell(student[:order].to_s, rowspan: ROWS_PER_STUDENT, align: :center, valign: :center),
      table_cell(
        highlighted_content(student_name, student_below_minimum),
        rowspan: ROWS_PER_STUDENT,
        align: :left,
        valign: :center,
        inline_format: student_below_minimum,
        background_color: student_below_minimum ? BELOW_MINIMUM_BACKGROUND : nil
      ),
      table_cell(student[:situation].to_s, rowspan: ROWS_PER_STUDENT, align: :center, valign: :center),
      table_cell(format_frequency(student[:frequency_percentage], student[:total_absences]), align: :center)
    ]

    @disciplines.each do |_discipline|
      first_row << table_cell('Notas', align: :center)
      first_row << table_cell('F', align: :center)
    end

    step_rows = student[:steps].first(ROWS_PER_STUDENT - 1).map do |step|
      row = [
        table_cell(step[:label], align: :center)
      ]

      step[:disciplines].each do |discipline_data|
        row << score_cell(discipline_data)
        row << table_cell(discipline_data[:absences].to_s, align: :center)
      end

      row
    end

    while step_rows.size < (ROWS_PER_STUDENT - 1)
      step_rows << empty_step_row
    end

    [first_row] + step_rows
  end

  def empty_step_row
    row = [table_cell('', align: :center)]

    @disciplines.each do |_discipline|
      row << table_cell('', align: :center)
      row << table_cell('', align: :center)
    end

    row
  end

  def layout_widths
    @layout_widths ||= calculate_layout_widths
  end

  def calculate_layout_widths
    order_w = 16
    situation_w = 16
    frequency_w = 46
    student_w = 95
    discipline_pairs = @disciplines.size
    min_pair_width = MIN_SCORE_WIDTH + MIN_ABSENCE_WIDTH

    if discipline_pairs.positive?
      available = bounds.width - order_w - situation_w - frequency_w - student_w

      if available < discipline_pairs * min_pair_width
        student_w = bounds.width - order_w - situation_w - frequency_w - (discipline_pairs * min_pair_width)
        student_w = [student_w, MIN_STUDENT_WIDTH].max
        available = bounds.width - order_w - situation_w - frequency_w - student_w
      end

      pair_width = available / discipline_pairs.to_f
      score_w = pair_width * 0.65
      absence_w = pair_width * 0.35

      if score_w < MIN_SCORE_WIDTH || absence_w < MIN_ABSENCE_WIDTH
        score_w = [score_w, MIN_SCORE_WIDTH].max
        absence_w = [absence_w, MIN_ABSENCE_WIDTH].max
        pair_total = score_w + absence_w

        if pair_total > pair_width
          scale = pair_width / pair_total
          score_w *= scale
          absence_w *= scale
        end
      end
    else
      score_w = MIN_SCORE_WIDTH
      absence_w = MIN_ABSENCE_WIDTH
    end

    student_w *= STUDENT_COLUMN_WIDTH_FACTOR
    score_w *= SCORE_COLUMN_WIDTH_FACTOR
    absence_w *= ABSENCE_COLUMN_WIDTH_FACTOR

    {
      order: order_w,
      student: student_w,
      situation: situation_w,
      frequency: frequency_w,
      score: score_w,
      absence: absence_w
    }
  end

  def column_widths_array
    widths = layout_widths
    columns = [widths[:order], widths[:student], widths[:situation], widths[:frequency]] +
              @disciplines.flat_map { [widths[:score], widths[:absence]] }

    normalize_column_widths(columns)
  end

  def normalize_column_widths(columns)
    total = columns.sum
    return columns if total.zero?

    scale = bounds.width / total
    normalized = columns.map { |width| width * scale }

    width_gap = bounds.width - normalized.sum
    normalized[-1] += width_gap if width_gap.abs > 0.01

    normalized
  end

  def content_font_size
    @content_font_size ||= if @disciplines.size > 18
                             5
                           elsif @disciplines.size > 14
                             5.5
                           else
                             FONT_SIZE
                           end
  end

  def table_cell(content, options = {})
    cell_options = { content: content.to_s, size: content_font_size }.merge(options)
    cell_options.reject! { |_key, value| value.nil? }

    make_cell(cell_options)
  end

  def score_cell(discipline_data)
    below_minimum = discipline_data[:below_minimum]
    formatted_score = format_score(discipline_data[:score])

    table_cell(
      highlighted_content(formatted_score, below_minimum),
      align: :center,
      inline_format: below_minimum,
      background_color: below_minimum ? BELOW_MINIMUM_BACKGROUND : nil
    )
  end

  def highlighted_content(text, highlight)
    return text unless highlight

    "<color rgb='#{BELOW_MINIMUM_COLOR}'><b>#{text}</b></color>"
  end

  def student_below_minimum?(student)
    student[:steps].any? do |step|
      step[:disciplines].any? { |discipline_data| discipline_data[:below_minimum] }
    end
  end

  def truncate_student_name(name)
    max_chars = (layout_widths[:student] / 2.8).floor
    max_chars = [[max_chars, 20].max, 60].min
    normalized_name = name.to_s.upcase

    return normalized_name if normalized_name.length <= max_chars

    "#{normalized_name[0, max_chars - 3]}..."
  end

  def format_frequency(percentage, absences)
    "#{format('%.2f', percentage)}% - #{absences}"
  end

  def format_score(score)
    return '' if score.blank?

    number_with_precision(score, precision: 1, separator: ',', delimiter: '.')
  end
end
