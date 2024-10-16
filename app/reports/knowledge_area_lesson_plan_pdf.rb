class KnowledgeAreaLessonPlanPdf < BaseReport
  def self.build(entity_configuration, knowledge_area_lesson_plan, current_teacher)
    new.build(entity_configuration, knowledge_area_lesson_plan, current_teacher)
  end

  def build(entity_configuration, knowledge_area_lesson_plan, current_teacher)
    @entity_configuration = entity_configuration
    @knowledge_area_lesson_plan = knowledge_area_lesson_plan
    @current_teacher = current_teacher
    attributes

    if @display_header_on_all_reports_pages
      header
      body
    else
      bounding_box([0, cursor], width: bounds.width, height: bounds.height - GAP) do
        header
        body
      end
    end

    footer

    self
  end

  private

  def header
    header_cell = make_cell(
      content: Translator.t('navigation.knowledge_area_lesson_plans'),
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
        image: open(@entity_configuration.logo.url),
        fit: [50, 50],
        width: 70,
        rowspan: 4,
        position: :center,
        vposition: :center
      )
    rescue StandardError
      entity_logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n#{@knowledge_area_lesson_plan.lesson_plan.unity.name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 4,
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
      colspan: 4
    )

    @class_plan_header_cell = make_cell(
      content: Translator.t('navigation.lesson_plans_menu'),
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 4
    )

    @additional_information_header_cell = make_cell(
      content: 'Informações adicionais',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 4
    )

    knowledge_area_lesson_plans_knowledge_areas = KnowledgeAreaLessonPlanKnowledgeArea.where knowledge_area_lesson_plan_id: @knowledge_area_lesson_plan.id

    knowledge_area_ids = []

    knowledge_area_lesson_plans_knowledge_areas.each do |knowledge_area_lesson_plans_knowledge_area|
      knowledge_area_ids << knowledge_area_lesson_plans_knowledge_area.knowledge_area_id
    end

    knowledge_areas = KnowledgeArea.where(id: knowledge_area_ids)

    knowledge_area_descriptions = knowledge_areas.map { |descriptions| descriptions }.join(', ')

    @teacher_header = make_cell(content: 'Professor', size: 8, font_style: :bold, borders: [:left, :right, :top], padding: [2, 2, 4, 4], colspan: 2)
    @teacher_cell = make_cell(content: @current_teacher.name, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 2)

    @unity_header = make_cell(content: 'Unidade', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 4)
    @unity_cell = make_cell(content: @knowledge_area_lesson_plan.lesson_plan.unity.name, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 4)

    @start_at_header = make_cell(content: 'Data inicial', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    @start_at_cell = make_cell(content: @knowledge_area_lesson_plan.lesson_plan.start_at.strftime('%d/%m/%Y'), size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])

    @end_at_header = make_cell(content: 'Data final', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    @end_at_cell = make_cell(content: @knowledge_area_lesson_plan.lesson_plan.end_at.strftime('%d/%m/%Y'), size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])

    @classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 2)
    @classroom_cell = make_cell(content: @knowledge_area_lesson_plan.lesson_plan.classroom.description, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 2)

    @knowledge_area_header = make_cell(content: 'Áreas de conhecimento', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 2)
    @knowledge_area_cell = make_cell(content: knowledge_area_descriptions, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], colspan: 2)

    if @knowledge_area_lesson_plan.experience_fields.present?
      experience_fields_cell_content = inline_formated_cell_header(
        Translator.t('activerecord.attributes.knowledge_area_lesson_plan.experience_fields')
      ) + @knowledge_area_lesson_plan.experience_fields

      @experience_fields_cell = make_cell(
        content: experience_fields_cell_content,
        size: 10,
        borders: [:bottom, :left, :right, :top],
        padding: [0, 2, 4, 4],
        colspan: 4
      )
    end

    contents = '-'
    if @knowledge_area_lesson_plan.lesson_plan.contents.present?
      contents = @knowledge_area_lesson_plan.lesson_plan.contents_ordered.map(&:to_s).join("\n ")
    end
    content_cell_content = inline_formated_cell_header(
      Translator.t('activerecord.attributes.knowledge_area_lesson_plan.contents')
    ) + contents
    @content_cell = make_cell(
      content: content_cell_content,
      size: 10,
      borders: [:bottom, :left, :right, :top],
      padding: [0, 2, 4, 4],
      colspan: 4
    )

    objectives = '-'
    if @knowledge_area_lesson_plan.lesson_plan.objectives.present?
      objectives = @knowledge_area_lesson_plan.lesson_plan.objectives_ordered.map(&:to_s).join("\n ")
    end
    objectives_cell_content = inline_formated_cell_header(
      Translator.t('activerecord.attributes.knowledge_area_lesson_plan.objectives')
    ) + objectives
    @objectives_cell = make_cell(
      content: objectives_cell_content,
      size: 10,
      borders: [:bottom, :left, :right, :top],
      padding: [0, 2, 4, 4],
      colspan: 4
    )

    opinion_cell_content = inline_formated_cell_header('Parecer') + @knowledge_area_lesson_plan.lesson_plan.opinion.to_s
    @opinion_cell = make_cell(content: opinion_cell_content, size: 10, borders: [:bottom, :left, :right, :top], padding: [0, 2, 4, 4], colspan: 4)
  end

  def removed_objectives?
    return false if GeneralConfiguration.current.remove_lesson_plan_objectives

    true
  end

  def identification
    identification_table_data = [
      [@identification_header_cell],
      [@unity_header],
      [@unity_cell],
      [@knowledge_area_header, @classroom_header],
      [@knowledge_area_cell, @classroom_cell],
      [@teacher_header, @start_at_header, @end_at_header],
      [@teacher_cell, @start_at_cell, @end_at_cell]
    ]

    table(identification_table_data, width: bounds.width) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def class_plan
    class_plan_table_data = if removed_objectives?
                              [
                                [@class_plan_header_cell],
                                [@content_cell],
                                [@objectives_cell]
                              ]
                            else
                              [
                                [@class_plan_header_cell],
                                [@content_cell]
                              ]
                            end

    if @knowledge_area_lesson_plan.experience_fields.present?
      class_plan_table_data.insert(1, [@experience_fields_cell])
    end

    table(class_plan_table_data, width: bounds.width, cell_style: { inline_format: true }) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    actives_methodology_translation = Translation.find_by(key: 'navigation.actives_methodology_by_discipline', group: 'lesson_plans').translation
    actives_methodology_label = actives_methodology_translation.present? ? actives_methodology_translation : 'Atividades/metodologia'

    resources_translation = Translation.find_by(key: 'navigation.resources_by_knowledge_area', group: 'lesson_plans').translation
    resources_label = resources_translation.present? ? resources_translation : 'Recursos'

    evaluation_translation = Translation.find_by(key: 'navigation.avaliation_by_knowledge_area', group: 'lesson_plans').translation
    evaluation_label = evaluation_translation.present? ? evaluation_translation : 'Avaliação'

    references_translation = Translation.find_by(key: 'navigation.references_by_knowledge_area', group: 'lesson_plans').translation
    references_label = references_translation.present? ? references_translation : 'Referências'

    text_box_truncate(actives_methodology_label, (@knowledge_area_lesson_plan.lesson_plan.activities || '-'))
    text_box_truncate(resources_label, (@knowledge_area_lesson_plan.lesson_plan.resources || '-'))
    text_box_truncate(evaluation_label, (@knowledge_area_lesson_plan.lesson_plan.evaluation || '-'))
    text_box_truncate(references_label, (@knowledge_area_lesson_plan.lesson_plan.bibliography || '-'))
  end

  def additional_information
    additional_information_table_data = [
      [@additional_information_header_cell],
      [@opinion_cell]
    ]

    if @knowledge_area_lesson_plan.lesson_plan.opinion.present?
      start_new_page if cursor < 45
      table(additional_information_table_data, width: bounds.width, cell_style: { inline_format: true }) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def body
    page_content do
      identification
      class_plan
      additional_information
    end
  end
end
