class DisciplinesSynchronizer < BaseSynchronizer
  def synchronize!
    update_records(
      HashDecorator.new(
        api.fetch['disciplinas']
      )
    )
  rescue IeducarApi::Base::ApiError => error
    synchronization.mark_as_error!(error.message)
  end

  private

  def api_class
    IeducarApi::Disciplines
  end

  def update_records(disciplines)
    disciplines.each do |discipline_record|
      Discipline.find_or_initialize_by(api_code: discipline_record.id).tap do |discipline|
        knowledge_area = knowledge_area(discipline_record.area_conhecimento_id)
        group_descriptors = knowledge_area.group_descriptors

        discipline.description = discipline_record.nome
        discipline.sequence = discipline_record.ordenamento
        discipline.knowledge_area = knowledge_area
        discipline.descriptor = group_descriptors
        discipline.disregard_for_progression = disregard_for_progression?(discipline_record)

        create_or_destroy_grouper_disciplines(knowledge_area) if group_descriptors

        discipline.save! if discipline.changed?
      end
    end
  end

  # modules.componente_curricular.desconsidera_para_progressao
  # ("Desconsiderar o componente na aprovação/reprovação dos alunos?").
  def disregard_for_progression?(discipline_record)
    value = discipline_record.desconsidera_para_progressao
    return false if [nil, false, 0, '0', 'f', 'F', 'false', 'FALSE', ''].include?(value)

    true
  end

  def create_or_destroy_grouper_disciplines(knowledge_area)
    if knowledge_area.group_descriptors
      Discipline.unscoped.find_or_initialize_by(
        knowledge_area_id: knowledge_area.id,
        grouper: true,
        api_code: "grouper:#{knowledge_area.id}"
      ).tap do |grouper_discipline|
        grouper_discipline.description = knowledge_area.description

        grouper_discipline.save!
      end
    else
      Discipline.unscoped.find_by(
        knowledge_area_id: knowledge_area.id,
        grouper: true,
        api_code: "grouper:#{knowledge_area.id}"
      )&.destroy
    end
  end
end
