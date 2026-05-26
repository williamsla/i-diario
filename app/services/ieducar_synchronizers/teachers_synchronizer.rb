require 'cpf_cnpj'

class TeachersSynchronizer < BaseSynchronizer
  def synchronize!
    update_teachers(
      HashDecorator.new(
        api.fetch['servidores']
      )
    )
  rescue IeducarApi::Base::ApiError => error
    synchronization.mark_as_error!(error.message || error.class.name)
  end

  private

  def api_class
    IeducarApi::Teachers
  end

  def update_teachers(teachers)
    
    teachers.each do |teacher_record|
      if teacher_record.nome.blank?
        Rails.logger.info("Nome do servidor não definido para o servidor ID: #{teacher_record.servidor_id}")
        next
      end

      teacher_record.cpf = teacher_record.cpf.strip if teacher_record.cpf

      Teacher.with_discarded.find_or_initialize_by(api_code: teacher_record.servidor_id).tap do |teacher|
        
        teacher.name = teacher_record.nome
        teacher.active = teacher_record.ativo.to_s == IeducarBooleanState::ACTIVE
        teacher.save! if teacher.changed?
        
        if CPF.valid?(teacher_record.cpf)
          Rails.logger.info("==\nCPF válido: #{teacher_record.cpf}")
          
          if teacher_record.cpf.contains?('136.121.734-05')
            Rails.logger.info("\n\n\n\n professora AMANDA...")            
          end

          user = User.by_cpf(teacher_record.cpf)          
          if user.exists?
            Rails.logger.info("== Atualizando usuário: #{user.id} Teacher ID: #{teacher.id} CPF: #{teacher_record.cpf} School ID: #{teacher_record.escola_id} Function Name: #{teacher_record.nm_funcao}")
            update_users(teacher.id, teacher_record.cpf, teacher_record.escola_id, teacher_record.nm_funcao)
          else
            Rails.logger.info("== Criando usuário: Teacher ID: #{teacher.id} CPF: #{teacher_record.cpf} School ID: #{teacher_record.escola_id} Function Name: #{teacher_record.nm_funcao}")
            create_users(teacher.id, teacher_record.cpf, teacher_record.escola_id, teacher_record.nm_funcao)
          end
        else
          Rails.logger.info("CPF inválido: #{teacher_record.cpf}")
          Rails.logger.info("Teacher: #{teacher.id}")
          Rails.logger.info("Teacher name: #{teacher.name}")
          Rails.logger.info("Teacher active: #{teacher.active}")
          Rails.logger.info("Teacher api_code: #{teacher.api_code}")
          Rails.logger.info("Teacher created_at: #{teacher.created_at}")
          Rails.logger.info("Teacher updated_at: #{teacher.updated_at}")
          Rails.logger.info("Teacher discarded_at: #{teacher.discarded_at}")
          Rails.logger.info("-------------------------------------------")
        end

      end
    end
  end

  def create_users(teacher_id, cpf, school_id, function_name)
    UserForTeacherCreatorWorker.perform_in(1.second, entity_id, teacher_id, cpf, school_id, function_name)
  end

  def update_users(teacher_id, cpf, school_id, function_name)
    UserForTeacherUpdaterWorker.perform_in(1.second, entity_id, teacher_id, cpf, school_id, function_name)
  end
  
end