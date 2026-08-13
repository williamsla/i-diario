class DisciplineLessonPlanReport < BaseReport
  def self.build(entity_configuration, unity, date_start, date_end, discipline_lesson_plan, current_teacher, classroom=nil)
    new.build(entity_configuration, unity, date_start, date_end, discipline_lesson_plan, current_teacher,classroom)
  end

  def build(entity_configuration, unity, date_start, date_end, discipline_lesson_plan, current_teacher, classroom)
    @entity_configuration = entity_configuration
    @unity = unity
    @date_start = date_start
    @date_end = date_end
    @discipline_lesson_plans = discipline_lesson_plan
    @current_teacher = current_teacher
    @classroom = classroom
    attributes

    header
    body
    footer

    self
  end

  private

  def header
    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''
    title =  'Registros de conteúdos por disciplina - Planos de aula'

    header_cell = make_cell(
      content: title,
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 2
    )

    begin
      entity_logo_cell = make_cell(
        image: entity_logo_io,
        fit: [50, 50],
        width: 70,
        rowspan: 1,
        position: :center,
        vposition: :center
      )
    rescue
      entity_logo_cell = make_cell(content: '', width: 70, rowspan: 1)
    end

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n" + "#{@discipline_lesson_plans.first.lesson_plan.unity.name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 1,
      padding: [6, 0, 8, 0]
    )

    table_data = [
      [header_cell],
      [
        entity_logo_cell,
        entity_organ_and_unity_cell
      ]
    ]

    page_header do
      table(table_data, width: bounds.width) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def attributes
    @identification_header_cell = make_cell(
      content: 'Identificação',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 2
    )

    @general_information_header_cell = make_cell(
      content: 'Informações gerais',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 5
    )

    @teacher_header = make_cell(content: 'Professor', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @unity_header = make_cell(content: 'Unidade', size: 8, font_style: :bold, borders: [:left, :right, :top], padding: [2, 2, 4, 4], colspan: 2)
    @discipline_header = make_cell(content: 'Disciplina', size: 8, font_style: :bold, borders: [:left, :right, :top], padding: [2, 2, 4, 4])
    @classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @period_header = make_cell(content: 'Período', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @unity_cell = make_cell(content:  @discipline_lesson_plans.first.lesson_plan.unity.name, borders: [:bottom, :left, :right], size: 10, width: 240, align: :left, padding: [0, 2, 4, 4], colspan: 2)
    @discipline_cell = make_cell(content: @discipline_lesson_plans.first.discipline.to_s, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @classroom_cell = make_cell(content: @discipline_lesson_plans.first.lesson_plan.classroom.description, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @teacher_cell = make_cell(content: @current_teacher.name, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @period_cell = make_cell(content: (@date_start == '' || @date_end == '' ? '-' : "#{@date_start} a #{@date_end}"), borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])

    @dates_header = make_cell(content: 'Datas', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 10, padding: [2, 2, 4, 4])
    @conteudo_header = make_cell(content: Translator.t('activerecord.attributes.discipline_content_record.contents'), size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 50, padding: [2, 2, 4, 4])
    @habilidade_header = make_cell(content: 'Habilidades', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 90, padding: [2, 2, 4, 4])
    
  end

  def identification
    identification_table_data = [
      [@identification_header_cell],
      [@unity_header],
      [@unity_cell],
      [@discipline_header, @classroom_header],
      [@discipline_cell, @classroom_cell],
      [@teacher_header, @period_header],
      [@teacher_cell, @period_cell]
    ]

    table(identification_table_data, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def general_information
    general_plans, individual_plans = partitioned_lesson_plans

    render_records_section('Informações gerais', general_plans) if general_plans.any?
    render_individual_records_section(individual_plans) if individual_plans.any?
  end

  def partitioned_lesson_plans
    plans = @discipline_lesson_plans.to_a
    general_plans = plans.select { |plan| plan.lesson_plan.student_id.blank? }
    individual_plans = plans.select { |plan| plan.lesson_plan.student_id.present? }

    [general_plans, individual_plans]
  end

  def render_individual_records_section(individual_plans)
    section_header_cell = make_cell(
      content: 'Registros individuais',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 3
    )

    move_down GAP
    start_new_content_page if cursor < 80

    table([[section_header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    grouped_by_student(individual_plans).each do |student, plans|
      render_student_group_header(student)
      render_records_table(plans)
    end
  end

  def grouped_by_student(individual_plans)
    individual_plans
      .group_by { |plan| plan.lesson_plan.student }
      .sort_by { |student, _plans| student.display_name.to_s }
  end

  def render_student_group_header(student)
    student_header_cell = make_cell(
      content: "Aluno: #{student}",
      size: 10,
      font_style: :bold,
      background_color: 'EEEEEE',
      padding: [4, 2, 4, 4],
      colspan: 3
    )

    start_new_content_page if cursor < 60

    table([[student_header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def render_records_section(title, plans)
    section_header_cell = make_cell(
      content: title,
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 3
    )

    table([[section_header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    render_records_table(plans)
  end

  def render_records_table(plans)
    headers = [
      make_cell(content: 'Datas', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 10, padding: [2, 2, 4, 4]),
      make_cell(content: Translator.t('activerecord.attributes.discipline_content_record.contents'), size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 50, padding: [2, 2, 4, 4]),
      make_cell(content: 'Habilidades', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 90, padding: [2, 2, 4, 4])
    ]

    table_data = [headers] + plans.map { |plan| lesson_plan_row(plan) }
    render_chunked_table(table_data)
  end

  def lesson_plan_row(discipline_lesson_plan)
    lesson_plan = discipline_lesson_plan.lesson_plan
    dates = "Início: #{lesson_plan.start_at.strftime('%d/%m/%Y')}\nFim: #{lesson_plan.end_at.strftime('%d/%m/%Y')}"
    texto_praticas_pedagogicas_e_habilidades = "#{lesson_plan.objectives_ordered.map(&:to_s).join(", ")}\n\n#{lesson_plan.activities.to_s.gsub(/<[^>]*>/, '')}"

    [
      make_cell(content: dates, size: 8, align: :left),
      make_cell(content: lesson_plan.contents_ordered.map(&:to_s).join(', '), size: 9, align: :left),
      make_cell(content: texto_praticas_pedagogicas_e_habilidades, size: 8, align: :left)
    ]
  end

  def body
    position_below_header
    identification
    general_information
    signatures
  end

  def signatures
    start_new_content_page if cursor < 45

    move_down 30
    text_box("______________________________________________\nProfessor(a)", size: 10, align: :center, at: [0, cursor], width: 260)
    text_box("______________________________________________\nCoordenador(a)/diretor(a)", size: 10, align: :center, at: [306, cursor], width: 260)
  end
end
