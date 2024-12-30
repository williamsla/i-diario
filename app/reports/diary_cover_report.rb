require 'hexapdf'

class DiaryCoverReport < BaseReport
    def self.build(pdfTarget, entity_configuration, unity, classroom, discipline, teacher, year)
      new.build(pdfTarget, entity_configuration, unity, classroom, discipline, teacher, year)
    end
  
    def build(pdfTarget, entity_configuration, unity, classroom, discipline, teacher, year)
      @pdfTarget = pdfTarget
      @entity_configuration = entity_configuration
      @unity = unity
      @classroom = classroom
      @discipline = discipline
      @teacher = teacher
      @year = year
    
      create

      self
    end
  
    private

    def create

      page = @pdfTarget.pages.add
      canvas = page.canvas
      canvas.font('Helvetica', size: 24)


      form = @pdfTarget.add({ Type: :XObject, Subtype: :Form, BBox: [0, 0, 100, 100]})
      form_canvas = form.canvas
      
      page_box = canvas.context.box
      canvas.rectangle(20, 20, page_box.width - 40, page_box.height - 40, radius: 5).stroke
      
      begin
        # unless @entity_configuration.logo.url.nil?
          # path = "#{Rails.root}/public#{@entity_configuration.logo.url}"
        canvas.image(open(@entity_configuration.logo.url), at: [250, 670], width: 70, height: 70)
        # end      
      rescue
        Rails.logger.error "Não não conseguiu carregar a imagem #{path}"
      end
      
      canvas.font('Helvetica', size: 14)
      x = calculate_xposition_to_center(@entity_configuration.entity_name.upcase.length, page_box.width)
      canvas.text(@entity_configuration.entity_name.upcase, at: [x, 650])
      x = calculate_xposition_to_center(@entity_configuration.organ_name.upcase.length, page_box.width)
      canvas.text(@entity_configuration.organ_name.upcase, at: [x, 630])

      canvas.font('Helvetica', size: 40)
      canvas.text("Diário de Classe", at: [160, 420])

      canvas.font('Helvetica', size: 14)

      
      case @classroom.period
      when Periods::FULL.to_s
        turno = "Integral"
      when Periods::MATUTINAL.to_s
        turno = "Matutino"
      when Periods::VESPERTINE.to_s
        turno = "Vespertino"
      when Periods::NIGHTLY.to_s
        turno = "Noturno"
      else
        turno = ""
      end
      
      y_position_info_escola = 200
      y_distance = 25
      
      canvas.text("Escola: #{@unity.name}", at:[30, y_position_info_escola])
      canvas.text("Ano letivo: #{@year}", at:[30, y_position_info_escola - 2*y_distance])
      canvas.text("Turma: #{@classroom.description}", at:[30, y_position_info_escola - 3*y_distance])
      canvas.text("Turno: #{turno}", at:[400, y_position_info_escola - 4*y_distance])
      canvas.text("Professor(a): #{@teacher.name}", at:[30, y_position_info_escola - 5*y_distance])
      #falta curso, série e disciplina
      
    end

    def calculate_xposition_to_center(text_size, line_size)
      pos = ((line_size - text_size)/2)/2
    end

  end
  