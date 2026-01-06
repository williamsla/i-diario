class StudentInFinalRecoveryDecorator
  include Decore
  include Decore::Proxy

  delegate :to_s, to: :component

  attr_writer :needed_score

  def needed_score
    return nil if @needed_score.nil?
    
    # Converte para float para garantir que valores acima de 10 sejam exibidos corretamente
    value = @needed_score.is_a?(Numeric) ? @needed_score : @needed_score.to_f
    
    # Formata o número preservando casas decimais, sem limitação de valor máximo
    # Usa number_with_precision para manter consistência com o sistema
    # precision: 1 garante 1 casa decimal, mas permite valores acima de 10
    ActionController::Base.helpers.number_with_precision(
      value,
      precision: 1,
      separator: ',',
      delimiter: '.'
    )
  end

  def self.primary_key
    Student.primary_key
  end

  def is_a?(klass)
    super || component.is_a?(klass)
  end
end
