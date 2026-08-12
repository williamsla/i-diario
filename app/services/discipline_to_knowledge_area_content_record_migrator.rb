class DisciplineToKnowledgeAreaContentRecordMigrator
  Result = Struct.new(:created, :skipped, :errors)

  def self.empty_result
    Result.new(0, 0, [])
  end

  def initialize(
    discipline_record_ids:,
    knowledge_area_ids: nil,
    dry_run: true,
    delete_old: false,
    skip_knowledge_area_check: false,
    verbose: false
  )
    @discipline_record_ids = Array(discipline_record_ids).map(&:to_i).uniq
    @knowledge_area_ids = Array(knowledge_area_ids).compact.map(&:to_i).uniq
    @dry_run = dry_run
    @delete_old = delete_old
    @skip_knowledge_area_check = skip_knowledge_area_check
    @verbose = verbose
  end

  def call
    result = self.class.empty_result

    if @knowledge_area_ids.present?
      knowledge_areas = KnowledgeArea.where(id: @knowledge_area_ids).to_a
      missing_ka_ids = @knowledge_area_ids - knowledge_areas.map(&:id)
      if missing_ka_ids.any?
        result.errors << "Área(s) de conhecimento não encontrada(s): #{missing_ka_ids.join(', ')}"
        return result
      end
    else
      knowledge_areas = nil
    end

    records = DisciplineContentRecord
      .where(id: @discipline_record_ids)
      .includes(discipline: :knowledge_area, content_record: [:contents, :objectives])

    missing_ids = @discipline_record_ids - records.map(&:id)
    missing_ids.each do |missing_id|
      result.errors << "Registro por disciplina ##{missing_id} não encontrado"
    end

    records.find_each do |discipline_record|
      migrate_record(discipline_record, knowledge_areas, result)
    end

    result
  end

  private

  def migrate_record(discipline_record, fixed_knowledge_areas, result)
    content_record = discipline_record.content_record
    classroom_id = content_record.classroom_id
    discipline = discipline_record.discipline

    target_areas = resolve_knowledge_areas(discipline_record, fixed_knowledge_areas, result)
    return if target_areas.nil?

    unless @skip_knowledge_area_check || knowledge_area_matches_discipline?(target_areas, discipline)
      area_ids = target_areas.map(&:id).join(', ')
      result.errors << error_message(
        discipline_record,
        "áreas (#{area_ids}) não incluem a área da disciplina #{discipline.description} (#{discipline.knowledge_area_id})"
      )
      return
    end

    if knowledge_area_content_record_exists?(content_record, classroom_id, target_areas)
      result.skipped += 1
      return
    end

    if @dry_run
      areas_label = target_areas.map(&:description).join(', ')
      puts "[DRY] DCR##{discipline_record.id} → #{areas_label} | #{content_record.record_date} | turma #{classroom_id}"
      result.created += 1
      return
    end

    ActiveRecord::Base.transaction do
      ka_content_record = build_knowledge_area_content_record(content_record, target_areas)
      validate_migration_prerequisites!(content_record, ka_content_record)
      ka_content_record.save!
      discipline_record.destroy! if @delete_old
      result.created += 1
    end
  rescue ActiveRecord::RecordInvalid => e
    log_exception(e, discipline_record)
    result.errors << error_message(discipline_record, e.record.errors.full_messages.join(', '))
  rescue StandardError => e
    log_exception(e, discipline_record)
    result.errors << error_message(discipline_record, exception_detail(e))
  end

  def resolve_knowledge_areas(discipline_record, fixed_knowledge_areas, result)
    return fixed_knowledge_areas if fixed_knowledge_areas.present?

    knowledge_area = discipline_record.discipline.knowledge_area
    unless knowledge_area
      result.errors << error_message(
        discipline_record,
        "disciplina #{discipline_record.discipline.description} sem área de conhecimento"
      )
      return nil
    end

    [knowledge_area]
  end

  def knowledge_area_matches_discipline?(target_areas, discipline)
    return true if discipline.knowledge_area_id.blank?

    target_areas.map(&:id).include?(discipline.knowledge_area_id)
  end

  def knowledge_area_content_record_exists?(content_record, classroom_id, target_areas)
    target_ids = target_areas.map(&:id).sort
    return false if target_ids.empty?

    base_query = KnowledgeAreaContentRecord
      .by_teacher_id(content_record_teacher_id(content_record))
      .by_classroom_id(classroom_id)
      .by_date(content_record.record_date)
      .by_student_id(content_record.student_id)

    matching_records = base_query
      .joins(:knowledge_areas)
      .where(knowledge_areas: { id: target_ids })
      .group('knowledge_area_content_records.id')
      .having('COUNT(DISTINCT knowledge_areas.id) = ?', target_ids.size)
      .select('knowledge_area_content_records.id')

    return false if matching_records.none?

    candidates = KnowledgeAreaContentRecord.where(id: matching_records.map(&:id)).includes(:knowledge_areas)
    candidates.any? { |record| record.knowledge_areas.map(&:id).sort == target_ids }
  end

  def build_knowledge_area_content_record(content_record, knowledge_areas)
    teacher_id = content_record_teacher_id(content_record)
    teacher = content_record.association(:teacher).reader || Teacher.find_by(id: teacher_id)

    ka_content_record = KnowledgeAreaContentRecord.new
    ka_content_record.teacher_id = teacher_id
    ka_content_record.knowledge_areas = knowledge_areas

    new_content_record = content_record.dup
    new_content_record.teacher = teacher if teacher.present?
    new_content_record.write_attribute(:teacher_id, teacher_id) if teacher_id.present?
    new_content_record.origin = OriginTypes::WEB
    new_content_record.creator_type = 'knowledge_area_content_record'
    new_content_record.original_contents = content_record.contents
    new_content_record.original_objectives = content_record.objectives
    new_content_record.objectives_created_at_position = {}
    content_record.objectives.each_with_index do |objective, position|
      new_content_record.objectives_created_at_position[objective.id] = position
    end
    new_content_record.daily_activities_record = content_record.daily_activities_record

    ka_content_record.content_record = new_content_record
    ka_content_record
  end

  def content_record_teacher_id(content_record)
    content_record.read_attribute(:teacher_id) ||
      content_record.association(:teacher).reader&.id
  end

  def validate_migration_prerequisites!(source_content_record, ka_content_record)
    teacher_id = content_record_teacher_id(source_content_record)

    if teacher_id.blank?
      raise "content_record ##{source_content_record.id} sem teacher_id no banco"
    end

    if ka_content_record.teacher_id.blank?
      raise "teacher_id não definido no KnowledgeAreaContentRecord (origem: teacher ##{teacher_id})"
    end
  end

  def exception_detail(exception)
    message = exception.message.presence
    if exception.is_a?(ArgumentError) && message.blank?
      message = 'provavelmente teacher_id ausente (TeacherRelationable#ensure_has_teacher_id_informed)'
    end

    [exception.class.name, message].compact.join(': ')
  end

  def log_exception(exception, discipline_record)
    header = "=== Erro ao migrar DCR##{discipline_record.id} (#{exception.class}) ==="
    detail = exception.message.presence || '(sem mensagem)'

    Rails.logger.error("#{header} #{detail}")
    Rails.logger.error(exception.backtrace.join("\n")) if exception.backtrace.present?

    return unless @verbose

    puts header
    puts detail
    puts exception.backtrace.first(20).join("\n") if exception.backtrace.present?
  end

  def error_message(discipline_record, message)
    detail = message.presence || 'erro desconhecido'
    "DCR##{discipline_record.id}: #{detail}"
  end
end
