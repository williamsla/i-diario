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
      next if teacher_record.nome.blank?

      teacher_record.cpf = teacher_record.cpf.strip if teacher_record.cpf

      Teacher.with_discarded.find_or_initialize_by(api_code: teacher_record.servidor_id).tap do |teacher|
        
        teacher.name = teacher_record.nome
        teacher.active = teacher_record.ativo.to_s == IeducarBooleanState::ACTIVE
        teacher.save! if teacher.changed?



        if CPF.valid?(teacher_record.cpf)
          
          user = User.by_cpf(teacher_record.cpf)
          
          if user.exists?
            update_users(teacher.id, teacher_record.cpf, teacher_record.escola_id, teacher_record.nm_funcao)
          else
            create_users(teacher.id, teacher_record.cpf, teacher_record.escola_id, teacher_record.nm_funcao)
          end
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