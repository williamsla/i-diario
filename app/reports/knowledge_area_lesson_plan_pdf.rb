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

    if @knowledge_area_lesson_plan.lesson_plan.student.present?
      @student_header = make_cell(content: 'Aluno', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], colspan: 4)
      @student_cell = make_cell(
        content: @knowledge_area_lesson_plan.lesson_plan.student.to_s,
        size: 10,
        font_style: :bold,
        borders: [:bottom, :left, :right],
        padding: [0, 2, 4, 4],
        colspan: 4
      )
    end

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
      [@knowledge_area_header, @classroom_header],
      [@knowledge_area_cell, @classroom_cell]
    ]

    if @student_header.present?
      identification_table_data << [@student_header]
      identification_table_data << [@student_cell]
    end

    identification_table_data += [
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

    actives_methodology_translation = Translation.find_by(key: 'navigation.actives_methodology_by_knowledge_area', group: 'lesson_plans').translation
    actives_methodology_label = actives_methodology_translation.present? ? actives_methodology_translation : 'Atividades/metodologia'

    resources_translation = Translation.find_by(key: 'navigation.resources_by_knowledge_area', group: 'lesson_plans').translation
    resources_label = resources_translation.present? ? resources_translation : 'Recursos'

    evaluation_translation = Translation.find_by(key: 'navigation.avaliation_by_knowledge_area', group: 'lesson_plans').translation
    evaluation_label = evaluation_translation.present? ? evaluation_translation : 'Avaliação'

    references_translation = Translation.find_by(key: 'navigation.references_by_knowledge_area', group: 'lesson_plans').translation
    references_label = references_translation.present? ? references_translation : 'Referências'

    begin
      activities_text = process_html_text(@knowledge_area_lesson_plan.lesson_plan.activities) || '-'
      text_box_dynamic_height(actives_methodology_label, activities_text)
    rescue => e
      Rails.logger.error "Erro ao renderizar atividades: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    
    begin
      resources_text = process_html_text(@knowledge_area_lesson_plan.lesson_plan.resources) || '-'
      text_box_dynamic_height(resources_label, resources_text)
    rescue => e
      Rails.logger.error "Erro ao renderizar recursos: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    
    begin
      evaluation_text = process_html_text(@knowledge_area_lesson_plan.lesson_plan.evaluation) || '-'
      text_box_dynamic_height(evaluation_label, evaluation_text)
    rescue => e
      Rails.logger.error "Erro ao renderizar avaliação: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    
    begin
      references_text = process_html_text(@knowledge_area_lesson_plan.lesson_plan.bibliography) || '-'
      text_box_dynamic_height(references_label, references_text)
    rescue => e
      Rails.logger.error "Erro ao renderizar referências: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def process_html_text(html_content)
    return nil if html_content.blank?
    
    begin
      # Processa o HTML para preservar quebras de linha e remover tags adequadamente
      processed_text = html_content.to_s
      # Converte tags de quebra de linha em quebras reais
      processed_text = processed_text.gsub(/<br\s*\/?>/i, "\n")
                                     .gsub(/<\/p>\s*<p[^>]*>/i, "\n\n")
                                     .gsub(/<\/div>\s*<div[^>]*>/i, "\n\n")
                                     .gsub(/<p[^>]*>/i, "")
                                     .gsub(/<\/p>/i, "\n")
                                     .gsub(/<div[^>]*>/i, "")
                                     .gsub(/<\/div>/i, "\n")
                                     .gsub(/<[^>]*>/, "") # Remove todas as outras tags HTML
                                     .gsub(/\n{3,}/, "\n\n") # Remove múltiplas quebras de linha consecutivas
                                     .strip
      
      processed_text.blank? ? nil : processed_text
    rescue => e
      Rails.logger.error "Erro ao processar HTML: #{e.message}"
      html_content.to_s.gsub(/<[^>]*>/, "") # Fallback: apenas remove tags
    end
  end

  def text_box_dynamic_height(title, information)
    return if information.blank?
    
    begin
      Rails.logger.debug "Iniciando text_box_dynamic_height para: #{title}"
      
      # Processa o HTML se necessário
      text_to_render = information.to_s
      if text_to_render.match(/<[^>]+>/)
        text_to_render = process_html_text(text_to_render) || text_to_render
      end
      
      return if text_to_render.blank?
      
      # Altura do título
      title_height = 12
      # Espaçamento entre título e texto
      title_spacing = 5
      # Padding para o texto
      padding = 10
      
      # Formata o texto preservando quebras de linha
      formatted_text = text_to_render.gsub("\n", "<br>")
      
      # Loop para continuar em novas páginas enquanto houver conteúdo
      remaining_text = formatted_text.to_s
      iteration_count = 0
      max_iterations = 50 # Proteção contra loop infinito
      
      while remaining_text.present? && remaining_text.to_s.strip.length > 0
        iteration_count += 1
        if iteration_count > max_iterations
          Rails.logger.error "Loop infinito detectado em text_box_dynamic_height para: #{title}"
          break
        end
        
        # Verifica se precisa de nova página antes de começar
        start_new_page if cursor < 60
        
        # Calcula o espaço disponível na página (reserva 20 pontos para footer)
        available_height = cursor - 20
        if available_height < 50
          Rails.logger.warn "Espaço insuficiente na página para: #{title}"
          break
        end
        
        # Calcula a altura real do texto
        begin
          text_height = height_of(remaining_text, width: bounds.width - 10, size: 10)
        rescue => e
          Rails.logger.error "Erro ao calcular altura do texto: #{e.message}"
          text_height = 100 # Altura padrão em caso de erro
        end
        
        # Calcula a altura máxima disponível para o texto (descontando título, espaçamento e padding)
        max_text_height_available = available_height - title_height - title_spacing - padding
        
        # Usa a altura real do texto ou o máximo disponível, o que for menor
        # Isso garante que a caixa se ajuste ao tamanho do texto
        text_height_available = [text_height, max_text_height_available].min
        
        # Garante altura mínima
        text_height_available = [text_height_available, 30].max
        
        # Altura da caixa (título + espaçamento + texto (real) + padding)
        box_height = title_height + title_spacing + text_height_available + padding
        
        # Garante que a altura da caixa não excede o disponível
        box_height = [box_height, available_height].min
        
        # Desenha a caixa completa
        bounding_box([0, cursor], width: bounds.width, height: box_height) do
          line_width 0.5
          stroke_bounds
          
          # Desenha o título dentro da caixa, no topo
          draw_text(title, size: 8, style: :bold, at: [5, box_height - 8])
          
          # Calcula posição para o texto (abaixo do título)
          text_y_position = box_height - title_height - title_spacing
          
          # Usa text_box com overflow para tratar o texto que não cabe
          begin
            remaining_text_result = text_box(
              remaining_text,
              width: bounds.width - 10,
              height: text_height_available,
              at: [5, text_y_position],
              overflow: :truncate,
              size: 10,
              inline_format: true
            )
            # Garante que remaining_text seja sempre uma String
            if remaining_text_result.is_a?(Array)
              # Se for Array de hashes, extrai o texto de cada hash
              remaining_text = remaining_text_result.map do |item|
                if item.is_a?(Hash)
                  item[:text] || item["text"] || ""
                else
                  item.to_s
                end
              end.join("")
            else
              remaining_text = remaining_text_result.to_s || ""
            end
          rescue => e
            Rails.logger.error "Erro ao renderizar text_box em #{title}: #{e.message}"
            Rails.logger.error e.backtrace.first(5).join("\n")
            remaining_text = ""
          end
        end
        
        # Se ainda há texto restante, continua em nova página
        # Garante que remaining_text seja sempre uma String
        if remaining_text.is_a?(Array)
          remaining_text = remaining_text.map do |item|
            if item.is_a?(Hash)
              item[:text] || item["text"] || ""
            else
              item.to_s
            end
          end.join("")
        end
        remaining_text = remaining_text.to_s if remaining_text.respond_to?(:to_s)
        remaining_text = "" if remaining_text.nil?
        
        if remaining_text.present? && remaining_text.to_s.strip.length > 0
          start_new_page
        else
          break
        end
      end
      
      move_down(5) # Espaçamento após a seção
      Rails.logger.debug "Finalizado text_box_dynamic_height para: #{title}"
    rescue => e
      Rails.logger.error "Erro em text_box_dynamic_height para #{title}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      # Continua mesmo com erro para não quebrar o PDF
      move_down(5)
    end
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
