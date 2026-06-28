class KnowledgeAreaToDisciplineContentRecordMigrator
  Result = Struct.new(:created, :skipped, :errors)

  def self.empty_result
    Result.new(0, 0, [])
  end

  def initialize(
    ka_record_ids:,
    discipline_id:,
    dry_run: true,
    delete_old: false,
    skip_knowledge_area_check: false,
    class_number: nil,
    verbose: false
  )
    @ka_record_ids = Array(ka_record_ids).map(&:to_i).uniq
    @discipline_id = discipline_id.to_i
    @dry_run = dry_run
    @delete_old = delete_old
    @skip_knowledge_area_check = skip_knowledge_area_check
    @class_number = class_number
    @verbose = verbose
  end

  def call
    result = self.class.empty_result

    discipline = Discipline.find_by(id: @discipline_id)
    unless discipline
      result.errors << "Disciplina #{@discipline_id} não encontrada"
      return result
    end

    records = KnowledgeAreaContentRecord
      .where(id: @ka_record_ids)
      .includes(:knowledge_areas, content_record: [:contents, :objectives])

    missing_ids = @ka_record_ids - records.map(&:id)
    missing_ids.each do |missing_id|
      result.errors << "Registro por área de conhecimento ##{missing_id} não encontrado"
    end

    records.find_each do |ka_record|
      migrate_record(ka_record, discipline, result)
    end

    result
  end

  private

  def migrate_record(ka_record, discipline, result)
    content_record = ka_record.content_record
    classroom_id = content_record.classroom_id

    unless discipline_in_classroom?(classroom_id)
      result.errors << error_message(ka_record, "disciplina #{@discipline_id} não está na turma #{classroom_id}")
      return
    end

    unless @skip_knowledge_area_check || knowledge_area_matches?(ka_record, discipline)
      ka_ids = ka_record.knowledge_areas.map(&:id).join(', ')
      result.errors << error_message(
        ka_record,
        "disciplina #{discipline.description} não pertence às áreas do registro (#{ka_ids})"
      )
      return
    end

    if discipline_content_record_exists?(content_record, classroom_id)
      result.skipped += 1
      return
    end

    if @dry_run
      puts "[DRY] KA##{ka_record.id} → #{discipline.description} | #{content_record.record_date} | turma #{classroom_id}"
      result.created += 1
      return
    end

    ActiveRecord::Base.transaction do
      discipline_content_record = build_discipline_content_record(content_record, discipline)
      validate_migration_prerequisites!(content_record, discipline_content_record)
      discipline_content_record.save!
      ka_record.destroy! if @delete_old
      result.created += 1
    end
  rescue ActiveRecord::RecordInvalid => e
    log_exception(e, ka_record)
    result.errors << error_message(ka_record, e.record.errors.full_messages.join(', '))
  rescue StandardError => e
    log_exception(e, ka_record)
    result.errors << error_message(ka_record, exception_detail(e))
  end

  def discipline_in_classroom?(classroom_id)
    Discipline.by_classroom_id(classroom_id).where(id: @discipline_id).exists?
  end

  def knowledge_area_matches?(ka_record, discipline)
    ka_record.knowledge_areas.map(&:id).include?(discipline.knowledge_area_id)
  end

  def discipline_content_record_exists?(content_record, classroom_id)
    DisciplineContentRecord
      .by_teacher_id(content_record_teacher_id(content_record))
      .by_classroom_id(classroom_id)
      .by_discipline_id(@discipline_id)
      .by_date(content_record.record_date)
      .exists?
  end

  def build_discipline_content_record(content_record, discipline)
    teacher_id = content_record_teacher_id(content_record)
    teacher = content_record.association(:teacher).reader || Teacher.find_by(id: teacher_id)

    discipline_content_record = DisciplineContentRecord.new(
      discipline: discipline,
      class_number: @class_number
    )
    discipline_content_record.teacher_id = teacher_id

    new_content_record = content_record.dup
    new_content_record.teacher = teacher if teacher.present?
    new_content_record.write_attribute(:teacher_id, teacher_id) if teacher_id.present?
    new_content_record.origin = OriginTypes::WEB
    new_content_record.creator_type = 'discipline_content_record'
    new_content_record.original_contents = content_record.contents
    new_content_record.original_objectives = content_record.objectives
    new_content_record.objectives_created_at_position = {}
    content_record.objectives.each_with_index do |objective, position|
      new_content_record.objectives_created_at_position[objective.id] = position
    end
    new_content_record.daily_activities_record = content_record.daily_activities_record

    discipline_content_record.content_record = new_content_record
    discipline_content_record
  end

  # TeacherRelationable define attr_accessor :teacher_id, que sobrescreve o getter
  # da coluna em ContentRecord. Use read_attribute para ler o valor real do banco.
  def content_record_teacher_id(content_record)
    content_record.read_attribute(:teacher_id) ||
      content_record.association(:teacher).reader&.id
  end

  def validate_migration_prerequisites!(source_content_record, discipline_content_record)
    teacher_id = content_record_teacher_id(source_content_record)

    if teacher_id.blank?
      raise "content_record ##{source_content_record.id} sem teacher_id no banco"
    end

    if discipline_content_record.teacher_id.blank?
      raise "teacher_id não definido no DisciplineContentRecord (origem: teacher ##{teacher_id})"
    end
  end

  def exception_detail(exception)
    message = exception.message.presence
    if exception.is_a?(ArgumentError) && message.blank?
      message = 'provavelmente teacher_id ausente (TeacherRelationable#ensure_has_teacher_id_informed)'
    end

    [exception.class.name, message].compact.join(': ')
  end

  def log_exception(exception, ka_record)
    header = "=== Erro ao migrar KA##{ka_record.id} (#{exception.class}) ==="
    detail = exception.message.presence || '(sem mensagem)'

    Rails.logger.error("#{header} #{detail}")
    Rails.logger.error(exception.backtrace.join("\n")) if exception.backtrace.present?

    return unless @verbose

    puts header
    puts detail
    puts exception.backtrace.first(20).join("\n") if exception.backtrace.present?
  end

  def error_message(ka_record, message)
    detail = message.presence || 'erro desconhecido'
    "KA##{ka_record.id}: #{detail}"
  end
end
