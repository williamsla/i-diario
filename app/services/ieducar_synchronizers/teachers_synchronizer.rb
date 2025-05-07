require 'cpf_cnpj'

class TeachersSynchronizer < BaseSynchronizer
  def synchronize!
    update_teachers(
      HashDecorator.new(
        api.fetch['servidores']
      )
    )
  rescue IeducarApi::Base::ApiError => error
    synchronization.mark_as_error!(error.message)
  end

  private

  def api_class
    IeducarApi::Teachers
  end

  def update_teachers(teachers)

    teachers.each do |teacher_record|
      next if teacher_record.nome.blank?

      Teacher.with_discarded.find_or_initialize_by(api_code: teacher_record.servidor_id).tap do |teacher|
        teacher.name = teacher_record.nome
        teacher.active = teacher_record.ativo.to_s == IeducarBooleanState::ACTIVE
        teacher.save! if teacher.changed?

        
        if CPF.valid?(teacher_record.cpf)
          Rails.logger.info "verificando se professor já existe"
          user = User.by_cpf(teacher_record.cpf)
          
          if user.exists?
            # TODO: atualizar o usuário
            Rails.logger.info "usuario do professor já existe #{user.inspect}"
            update_users(teacher.id, teacher_record.cpf, teacher_record.escola_id)
          else
            Rails.logger.info "usuario do professor não existe #{teacher.inspect}"
            create_users(teacher.id, teacher_record.cpf)
          end
        end

      end
    end
  end

  def create_users(teacher_id, cpf)
    UserForTeacherCreatorWorker.perform_in(1.second, entity_id, teacher_id, cpf)
  end

  def update_users(teacher_id, cpf, school_id)
    UserForTeacherCreatorWorker.perform_in(1.second, entity_id, teacher_id, cpf, school_id)
  end
  
end