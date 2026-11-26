class DisciplineToKnowledgeAreaLessonPlanMigrator
  Result = Struct.new(:created, :skipped, :errors)

  def self.empty_result
    Result.new(0, 0, [])
  end

  def initialize(
    discipline_lesson_plan_ids:,
    knowledge_area_ids: nil,
    dry_run: true,
    delete_old: false,
    skip_knowledge_area_check: false,
    verbose: false
  )
    @discipline_lesson_plan_ids = Array(discipline_lesson_plan_ids).map(&:to_i).uniq
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

    records = DisciplineLessonPlan
      .where(id: @discipline_lesson_plan_ids)
      .includes(
        { discipline: :knowledge_area },
        lesson_plan: [:contents, :objectives, :lesson_plan_attachments, :teacher]
      )

    missing_ids = @discipline_lesson_plan_ids - records.map(&:id)
    missing_ids.each do |missing_id|
      result.errors << "Plano de aula por disciplina ##{missing_id} não encontrado"
    end

    records.find_each do |discipline_lesson_plan|
      migrate_plan(discipline_lesson_plan, knowledge_areas, result)
    end

    result
  end

  private

  def migrate_plan(discipline_lesson_plan, fixed_knowledge_areas, result)
    lesson_plan = discipline_lesson_plan.lesson_plan
    classroom_id = lesson_plan.classroom_id
    discipline = discipline_lesson_plan.discipline

    target_areas = resolve_knowledge_areas(discipline_lesson_plan, fixed_knowledge_areas, result)
    return if target_areas.nil?

    unless @skip_knowledge_area_check || knowledge_area_matches_discipline?(target_areas, discipline)
      area_ids = target_areas.map(&:id).join(', ')
      result.errors << error_message(
        discipline_lesson_plan,
        "áreas (#{area_ids}) não incluem a área da disciplina #{discipline.description} (#{discipline.knowledge_area_id})"
      )
      return
    end

    if @dry_run
      areas_label = target_areas.map(&:description).join(', ')
      puts "[DRY] DLP##{discipline_lesson_plan.id} → #{areas_label} | #{lesson_plan.start_at} a #{lesson_plan.end_at} | turma #{classroom_id}"
      result.created += 1
      return
    end

    ActiveRecord::Base.transaction do
      original_attachments = {}
      ka_lesson_plan = build_knowledge_area_lesson_plan(discipline_lesson_plan, target_areas, original_attachments)
      validate_migration_prerequisites!(lesson_plan, ka_lesson_plan)
      ka_lesson_plan.save!
      copy_attachments!(ka_lesson_plan, original_attachments)
      discipline_lesson_plan.destroy! if @delete_old
      result.created += 1
    end
  rescue ActiveRecord::RecordInvalid => e
    log_exception(e, discipline_lesson_plan)
    result.errors << error_message(discipline_lesson_plan, e.record.errors.full_messages.join(', '))
  rescue StandardError => e
    log_exception(e, discipline_lesson_plan)
    result.errors << error_message(discipline_lesson_plan, exception_detail(e))
  end

  def resolve_knowledge_areas(discipline_lesson_plan, fixed_knowledge_areas, result)
    return fixed_knowledge_areas if fixed_knowledge_areas.present?

    knowledge_area = discipline_lesson_plan.discipline.knowledge_area
    unless knowledge_area
      result.errors << error_message(
        discipline_lesson_plan,
        "disciplina #{discipline_lesson_plan.discipline.description} sem área de conhecimento"
      )
      return nil
    end

    [knowledge_area]
  end

  def knowledge_area_matches_discipline?(target_areas, discipline)
    return true if discipline.knowledge_area_id.blank?

    target_areas.map(&:id).include?(discipline.knowledge_area_id)
  end

  def build_knowledge_area_lesson_plan(discipline_lesson_plan, knowledge_areas, original_attachments)
    lesson_plan = discipline_lesson_plan.lesson_plan
    teacher_id = lesson_plan_teacher_id(lesson_plan)
    teacher = lesson_plan.association(:teacher).reader || Teacher.find_by(id: teacher_id)

    new_lesson_plan = lesson_plan.dup
    new_lesson_plan.teacher = teacher if teacher.present?
    new_lesson_plan.write_attribute(:teacher_id, teacher_id) if teacher_id.present?
    assign_contents(new_lesson_plan, lesson_plan)
    assign_objectives(new_lesson_plan, lesson_plan)
    copy_attachment_records(new_lesson_plan, lesson_plan, original_attachments)

    ka_lesson_plan = KnowledgeAreaLessonPlan.new
    ka_lesson_plan.teacher_id = teacher_id
    ka_lesson_plan.knowledge_areas = knowledge_areas
    ka_lesson_plan.experience_fields = discipline_lesson_plan.thematic_unit
    ka_lesson_plan.lesson_plan = new_lesson_plan
    ka_lesson_plan
  end

  def assign_contents(new_lesson_plan, lesson_plan)
    contents = lesson_plan.contents_ordered.to_a
    new_lesson_plan.original_contents = contents
    new_lesson_plan.contents_created_at_position = {}
    contents.each_with_index do |content, position|
      new_lesson_plan.contents_created_at_position[content.id] = position
    end
  end

  def assign_objectives(new_lesson_plan, lesson_plan)
    objectives = lesson_plan.objectives_ordered.to_a
    new_lesson_plan.original_objectives = objectives
    new_lesson_plan.objectives_created_at_position = {}
    objectives.each_with_index do |objective, position|
      new_lesson_plan.objectives_created_at_position[objective.id] = position
    end
  end

  def copy_attachment_records(new_lesson_plan, lesson_plan, original_attachments)
    lesson_plan.lesson_plan_attachments.each do |attachment|
      filename = attachment.filename
      original_attachments[filename] = attachment.id if filename.present?
      new_lesson_plan.lesson_plan_attachments << attachment.dup
    end
  end

  def copy_attachments!(ka_lesson_plan, original_attachments)
    return if original_attachments.blank?

    LessonPlanAttachmentCopier.copy!(ka_lesson_plan.id, 'KnowledgeAreaLessonPlan', original_attachments)
  end

  def lesson_plan_teacher_id(lesson_plan)
    lesson_plan.read_attribute(:teacher_id) ||
      lesson_plan.association(:teacher).reader&.id
  end

  def validate_migration_prerequisites!(source_lesson_plan, ka_lesson_plan)
    teacher_id = lesson_plan_teacher_id(source_lesson_plan)

    if teacher_id.blank?
      raise "lesson_plan ##{source_lesson_plan.id} sem teacher_id no banco"
    end

    if ka_lesson_plan.teacher_id.blank?
      raise "teacher_id não definido no KnowledgeAreaLessonPlan (origem: teacher ##{teacher_id})"
    end
  end

  def exception_detail(exception)
    message = exception.message.presence
    if exception.is_a?(ArgumentError) && message.blank?
      message = 'provavelmente teacher_id ausente (TeacherRelationable#ensure_has_teacher_id_informed)'
    end

    [exception.class.name, message].compact.join(': ')
  end

  def log_exception(exception, discipline_lesson_plan)
    header = "=== Erro ao migrar DLP##{discipline_lesson_plan.id} (#{exception.class}) ==="
    detail = exception.message.presence || '(sem mensagem)'

    Rails.logger.error("#{header} #{detail}")
    Rails.logger.error(exception.backtrace.join("\n")) if exception.backtrace.present?

    return unless @verbose

    puts header
    puts detail
    puts exception.backtrace.first(20).join("\n") if exception.backtrace.present?
  end

  def error_message(discipline_lesson_plan, message)
    detail = message.presence || 'erro desconhecido'
    "DLP##{discipline_lesson_plan.id}: #{detail}"
  end
end
