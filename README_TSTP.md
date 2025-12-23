# Solução para Sinal TSTP no Sidekiq (ruby-timer-thr)

## Problema
O Sidekiq está recebendo sinais TSTP repetidamente, fazendo com que pare de aceitar novos trabalhos. 
Isso é causado pelo `ruby-timer-thr` (thread de timer do Ruby) que envia sinais TSTP incorretamente.

## Solução Implementada

Foi criado o arquivo `config/initializers/sidekiq_tstp_handler.rb` que:

1. **Intercepta sinais TSTP** quando o Sidekiq está rodando como servidor
2. **Ignora os sinais** para manter o Sidekiq funcionando normalmente
3. **Registra no log** quando recebe um sinal TSTP (para monitoramento)

## Como Funciona

O initializer verifica se:
- O Sidekiq está definido e rodando como servidor (`Sidekiq.server?`)
- A variável de ambiente `SIDEKIQ_IGNORE_TSTP` não está definida como `false`

Por padrão, o handler está **ATIVO** e ignora sinais TSTP.

## Uso

### Padrão (Recomendado)
O handler está ativo automaticamente. Apenas reinicie o Sidekiq:

```bash
bundle exec sidekiq -C config/sidekiq.yml
```

### Desabilitar o Handler (não recomendado)
Se por algum motivo precisar desabilitar:

```bash
SIDEKIQ_IGNORE_TSTP=false bundle exec sidekiq -C config/sidekiq.yml
```

## Verificação

Após reiniciar o Sidekiq, você deve ver no log:

```
[Sidekiq] Handler TSTP configurado - sinais TSTP serão ignorados
```

E quando receber um sinal TSTP (que será ignorado):

```
[Sidekiq] Sinal TSTP recebido mas ignorado (ruby-timer-thr workaround)
```

## Notas

- Esta solução é **segura** e não afeta o funcionamento normal do Sidekiq
- O Sidekiq continuará processando trabalhos normalmente
- Sinais TERM (para parar o Sidekiq) continuam funcionando normalmente
- Apenas sinais TSTP são ignorados

## Referências

- [Sidekiq Signals](https://github.com/sidekiq/sidekiq/wiki/Signals)
- [Ruby Signal Handling](https://ruby-doc.org/core-2.4.0/Signal.html)

