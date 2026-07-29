class ClassCouncilReport < BaseReport
  MAX_STEPS = 4
  FONT_SIZE = 6
  HEADER_BG = 'DEDEDE'
  SUBHEADER_BG = 'EFEFEF'
  BELOW_MINIMUM_BACKGROUND = 'FFE5E5'
  MIN_STUDENT_WIDTH = 55
  MIN_SCORE_WIDTH = 14
  MIN_ABSENCE_WIDTH = 10
  # Prawn: [top, right, bottom, left]
  CELL_PADDING = [3, 2, 3, 2].freeze
  ROW_HEIGHT = 16

  def self.build(entity_configuration, report_data)
    new(:landscape).build(entity_configuration, report_data)
  end

  def self.build_unavailable(entity_configuration, classroom)
    new(:landscape).build_unavailable(entity_configuration, classroom)
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

  def build_unavailable(entity_configuration, classroom)
    @entity_configuration = entity_configuration
    @classroom = classroom
    @report_data = ClassCouncilReportDataService.header_payload(classroom)
    @disciplines = []
    @steps = []
    @students = []

    header
    move_down 40
    text(
      I18n.t(
        'pedagogical_trackings.class_council_pdf.no_numeric_or_concept_scores',
        classroom: classroom.description
      ),
      size: 12,
      align: :center,
      style: :bold
    )
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
      column_headers + student_rows,
      width: bounds.width,
      column_widths: column_widths_array,
      header: true,
      cell_style: {
        size: font_size,
        padding: CELL_PADDING,
        valign: :center,
        align: :center,
        inline_format: false
      }
    ) do
      cells.border_width = 0.25
      row(0).background_color = HEADER_BG
      row(0).font_style = :bold
      row(1).background_color = SUBHEADER_BG
      row(1).font_style = :bold
    end
  end

  def column_headers
    top = [
      header_cell('Ord.', rowspan: 2),
      header_cell('Aluno', rowspan: 2),
      header_cell('Sit.', rowspan: 2),
      header_cell('Freq. - Falta', rowspan: 2),
      header_cell('Etapa', rowspan: 2)
    ]

    @disciplines.each do |discipline|
      top << header_cell(discipline[:abbreviation], colspan: 2)
    end

    bottom = @disciplines.flat_map do
      [
        header_cell('N', background_color: SUBHEADER_BG),
        header_cell('F', background_color: SUBHEADER_BG)
      ]
    end

    [top, bottom]
  end

  def header_cell(content, options = {})
    table_cell(
      content,
      {
        align: :center,
        valign: :center,
        font_style: :bold,
        background_color: HEADER_BG
      }.merge(options)
    )
  end

  def student_rows
    rows = []

    @students.each do |student|
      rows.concat(student_block_rows(student))
    end

    rows
  end

  def rows_per_student
    @rows_per_student ||= [[@steps.size, 1].max, MAX_STEPS].min
  end

  def student_block_rows(student)
    student_below_minimum = student_below_minimum?(student)
    student_name = wrap_student_name(student[:name])
    steps = Array(student[:steps]).first(rows_per_student)
    rowspan = [steps.size, 1].max

    first_step = steps.first || { label: '1º', disciplines: [] }

    first_row = [
      table_cell(student[:order].to_s, rowspan: rowspan, align: :center, valign: :center),
      student_name_cell(student_name, student_below_minimum, rowspan),
      table_cell(student[:situation].to_s, rowspan: rowspan, align: :center, valign: :center),
      table_cell(
        format_frequency(student[:frequency_percentage], student[:total_absences]),
        rowspan: rowspan,
        align: :center,
        valign: :center
      ),
      data_cell(step_label(first_step))
    ]

    append_discipline_cells!(first_row, first_step)

    other_rows = steps.drop(1).map do |step|
      row = [data_cell(step_label(step))]
      append_discipline_cells!(row, step)
      row
    end

    while other_rows.size < (rowspan - 1)
      other_rows << empty_step_row
    end

    [first_row] + other_rows
  end

  def append_discipline_cells!(row, step)
    disciplines_data = Array(step[:disciplines])

    @disciplines.each_with_index do |_discipline, index|
      discipline_data = disciplines_data[index] || { score: nil, absences: 0, below_minimum: false }
      row << score_cell(discipline_data)
      row << data_cell(discipline_data[:absences].to_s)
    end
  end

  def step_label(step)
    label = step[:label].to_s
    return label if label.length <= 4

    # "1º Bimestre" -> "1º"
    label[/\A\d+º/] || label
  end

  def student_name_cell(name, below_minimum, rowspan)
    options = {
      rowspan: rowspan,
      align: :left,
      valign: :center,
      leading: 1.5,
      inline_format: false,
      overflow: :shrink_to_fit,
      min_font_size: 4
    }
    options[:background_color] = BELOW_MINIMUM_BACKGROUND if below_minimum

    table_cell(name, options)
  end

  def empty_step_row
    row = [data_cell('')]

    @disciplines.each do |_discipline|
      row << data_cell('')
      row << data_cell('')
    end

    row
  end

  def data_cell(content, options = {})
    table_cell(
      content,
      {
        align: :center,
        valign: :center,
        height: ROW_HEIGHT
      }.merge(options)
    )
  end

  def layout_widths
    @layout_widths ||= calculate_layout_widths
  end

  def calculate_layout_widths
    order_w = 16
    situation_w = 16
    frequency_w = 42
    step_w = 22
    student_w = 90
    discipline_pairs = @disciplines.size
    min_pair_width = MIN_SCORE_WIDTH + MIN_ABSENCE_WIDTH
    fixed_without_student = order_w + situation_w + frequency_w + step_w

    if discipline_pairs.positive?
      available = bounds.width - fixed_without_student - student_w

      if available < discipline_pairs * min_pair_width
        student_w = bounds.width - fixed_without_student - (discipline_pairs * min_pair_width)
        student_w = [student_w, MIN_STUDENT_WIDTH].max
        available = bounds.width - fixed_without_student - student_w
      end

      pair_width = [available / discipline_pairs.to_f, min_pair_width].max
      score_w = [pair_width * 0.62, MIN_SCORE_WIDTH].max
      absence_w = [pair_width - score_w, MIN_ABSENCE_WIDTH].max
      score_w = pair_width - absence_w if score_w + absence_w > pair_width
    else
      score_w = MIN_SCORE_WIDTH
      absence_w = MIN_ABSENCE_WIDTH
    end

    {
      order: order_w,
      student: student_w,
      situation: situation_w,
      frequency: frequency_w,
      step: step_w,
      score: score_w,
      absence: absence_w
    }
  end

  def column_widths_array
    @column_widths_array ||= begin
      widths = layout_widths
      columns = [
        widths[:order],
        widths[:student],
        widths[:situation],
        widths[:frequency],
        widths[:step]
      ] + @disciplines.flat_map { [widths[:score], widths[:absence]] }

      normalize_column_widths(columns)
    end
  end

  def normalize_column_widths(columns)
    total = columns.sum
    return columns if total.zero?

    columns = columns.map { |width| width * (bounds.width / total) } if total > bounds.width

    score_start = 5
    (score_start...columns.size).step(2) { |index| columns[index] = [columns[index], MIN_SCORE_WIDTH].max }
    ((score_start + 1)...columns.size).step(2) { |index| columns[index] = [columns[index], MIN_ABSENCE_WIDTH].max }
    columns[1] = [columns[1], MIN_STUDENT_WIDTH].max

    if columns.sum > bounds.width
      overflow = columns.sum - bounds.width
      student_shrinkable = columns[1] - MIN_STUDENT_WIDTH

      if student_shrinkable.positive?
        shrink_by = [student_shrinkable, overflow].min
        columns[1] -= shrink_by
        overflow -= shrink_by
      end

      if overflow.positive?
        scale = bounds.width / columns.sum
        columns = columns.map { |width| width * scale }
      end
    end

    width_gap = bounds.width - columns.sum
    columns[-1] += width_gap if width_gap.abs > 0.01

    columns
  end

  def content_font_size
    @content_font_size ||= begin
      pair_width = layout_widths[:score] + layout_widths[:absence]

      if @disciplines.size > 24 || pair_width < 16
        4.5
      elsif @disciplines.size > 18 || pair_width < 18
        5
      elsif @disciplines.size > 14
        5.5
      else
        FONT_SIZE
      end
    end
  end

  def table_cell(content, options = {})
    cell_options = {
      content: content.to_s,
      size: content_font_size,
      padding: CELL_PADDING,
      valign: :center,
      align: :center,
      inline_format: false
    }.merge(options)
    cell_options.reject! { |_key, value| value.nil? }

    make_cell(cell_options)
  end

  def score_cell(discipline_data)
    below_minimum = discipline_data[:below_minimum]
    formatted_score = format_score(discipline_data[:score])
    options = {
      align: :center,
      valign: :center,
      height: ROW_HEIGHT,
      inline_format: false
    }
    options[:background_color] = BELOW_MINIMUM_BACKGROUND if below_minimum

    table_cell(formatted_score, options)
  end

  def student_below_minimum?(student)
    student[:steps].any? do |step|
      step[:disciplines].any? { |discipline_data| discipline_data[:below_minimum] }
    end
  end

  def wrap_student_name(name)
    full_name = name.to_s.upcase
    horizontal_padding = CELL_PADDING[1] + CELL_PADDING[3]
    max_width = student_column_width - horizontal_padding - 2
    font_size = content_font_size

    return full_name if max_width <= 0

    lines = []
    current_line = ''

    full_name.split(/\s+/).each do |word|
      break_long_word(word, max_width, font_size).split("\n").each_with_index do |segment, index|
        if index.positive?
          lines << current_line if current_line.present?
          current_line = segment
          next
        end

        candidate = current_line.blank? ? segment : "#{current_line} #{segment}"

        if text_fits?(candidate, max_width, font_size)
          current_line = candidate
        else
          lines << current_line if current_line.present?
          current_line = segment
        end
      end
    end

    lines << current_line if current_line.present?
    lines.join("\n")
  end

  def break_long_word(word, max_width, font_size)
    return word if text_fits?(word, max_width, font_size)

    segments = []
    current_segment = ''

    word.each_char do |char|
      candidate = "#{current_segment}#{char}"

      if text_fits?(candidate, max_width, font_size)
        current_segment = candidate
      else
        segments << current_segment if current_segment.present?
        current_segment = char
      end
    end

    segments << current_segment if current_segment.present?
    segments.join("\n")
  end

  def text_fits?(text, max_width, font_size)
    width_of(text, size: font_size) <= max_width
  end

  def student_column_width
    @student_column_width ||= column_widths_array[1]
  end

  def format_frequency(percentage, absences)
    "#{format('%.2f', percentage)}% - #{absences}"
  end

  def format_score(score)
    return '' if score.blank?

    if score.is_a?(Numeric)
      number_with_precision(score, precision: 1, separator: ',', delimiter: '.')
    else
      score.to_s
    end
  end
end
