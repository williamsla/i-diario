# Handler para ignorar sinal TSTP no Sidekiq
# Este initializer resolve o problema do ruby-timer-thr enviando sinais TSTP
# no servidor Contabo
#
# O ruby-timer-thr (thread de timer do Ruby) pode estar enviando sinais TSTP
# incorretamente, fazendo com que o Sidekiq pare de aceitar novos trabalhos.
# Este handler ignora esses sinais para manter o Sidekiq funcionando normalmente.

# Verificar se deve ignorar TSTP (pode ser controlado por variável de ambiente)
ignore_tstp = ENV.fetch('SIDEKIQ_IGNORE_TSTP', 'true').downcase == 'true'

if ignore_tstp
  # Definir o handler TSTP que será usado
  # IMPORTANTE: Não usar Rails.logger dentro do trap - usar STDERR ou arquivo diretamente
  tstp_handler = proc do
    STDERR.puts "[#{Time.now.utc.iso8601}] [Sidekiq] Sinal TSTP recebido mas ignorado (ruby-timer-thr workaround)"
    # Não fazer nada - o Sidekiq continuará funcionando normalmente
    # Isso evita que o Sidekiq pare de aceitar novos trabalhos
  end

  # Configurar o handler ANTES do Sidekiq inicializar (fallback inicial)
  Signal.trap('TSTP', &tstp_handler)

  # Configurar o handler dentro do configure_server
  Sidekiq.configure_server do |config|
    # Configurar o handler imediatamente
    Signal.trap('TSTP', &tstp_handler)
    Rails.logger.info "[Sidekiq] Handler TSTP configurado no configure_server"

    # O Sidekiq configura seus próprios handlers DEPOIS do configure_server,
    # então precisamos reconfigurar o handler continuamente após a inicialização
    # para garantir que sempre sobrescrevemos o handler do Sidekiq
    Thread.new do
      # Aguardar para que o Sidekiq termine de inicializar e configurar seus handlers
      sleep 2
      
      # Reconfigurar o handler para sobrescrever o handler do Sidekiq
      Signal.trap('TSTP', &tstp_handler)
      Rails.logger.info "[Sidekiq] Handler TSTP reconfigurado após inicialização do Sidekiq"
      
      # Monitorar e reconfigurar o handler muito frequentemente (a cada 0.5 segundos)
      # para garantir que ele permaneça ativo e sempre sobrescreva o handler do Sidekiq
      # Isso é necessário porque o Sidekiq pode reconfigurar o handler em certas situações
      loop do
        sleep 0.5
        # Reconfigurar o handler para garantir que ele ainda está ativo
        Signal.trap('TSTP', &tstp_handler)
        
        # Verificar periodicamente se o Sidekiq entrou em modo quiet e tentar despausar
        # Isso é uma verificação adicional caso o handler não tenha sido suficiente
        begin
          # Verificar a cada 5 segundos (não a cada loop para não sobrecarregar)
          @last_quiet_check ||= Time.now
          if Time.now - @last_quiet_check >= 5
            @last_quiet_check = Time.now
            process_set = Sidekiq::ProcessSet.new
            process_set.each do |process|
              if process['quiet'] == true && Process.pid.to_s == process['pid'].to_s
                STDERR.puts "[#{Time.now.utc.iso8601}] [Sidekiq] AVISO: Processo detectado em modo quiet apesar do handler TSTP"
                STDERR.puts "[#{Time.now.utc.iso8601}] [Sidekiq] Enviando sinal CONT para despausar"
                # Enviar sinal CONT para despausar o processo atual
                Process.kill('CONT', Process.pid) rescue nil
              end
            end
          end
        rescue => e
          # Ignorar erros na verificação (pode falhar em certas situações)
        end
      end
    end
  end
else
  Rails.logger.info "[Sidekiq] Handler TSTP desabilitado (SIDEKIQ_IGNORE_TSTP=false)"
end

