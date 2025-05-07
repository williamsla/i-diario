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
          
          user = User.by_cpf(teacher_record.cpf)
          
          # Se não encontrar e CPF começa com zero, tenta novamente sem o zero à esquerda
          if !user.exists? && teacher_record.cpf.start_with?("0")
            cpf_sem_zero = teacher_record.cpf.sub(/^0+/, "")
            user = User.by_cpf(cpf_sem_zero)
          end
          
          if user.exists?
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
    UserForTeacherUpdaterWorker.perform_in(1.second, entity_id, teacher_id, cpf, school_id)
  end
  
end