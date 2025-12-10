if Rails.application.secrets[:REDIS_MODE] == 'sentinel'
  # --- MODO SENTINEL ---
  config_redis_sidekiq = {
    url: "#{Rails.application.secrets[:REDIS_URL]}#{Rails.application.secrets[:REDIS_DB_SIDEKIQ]}",
    role: "master",
    sentinels: Rails.application.secrets[:REDIS_SENTINELS].split(";").map { |host| { host: host, port: 26379 } },
    reconnect_attempts: 3,
    network_timeout: 5
  }

else
  # --- MODO STANDALONE ---
  config_redis_sidekiq = {
    url: "#{Rails.application.secrets[:REDIS_URL]}#{Rails.application.secrets[:REDIS_DB_SIDEKIQ]}",
    reconnect_attempts: 3,
    network_timeout: 5
  }
end

# --- IMPORTANTE: Use ConnectionPool para a variável global ---
# --- Redis padrão da aplicação (usado em sincronizações e jobs customizados) ---
$REDIS_DB = ConnectionPool.new(size: 10, timeout: 5) do
  Redis.new(config_redis_sidekiq)
end

# --- Sidekiq com pool maior ---
Sidekiq.configure_server do |config|
  config.redis = config_redis_sidekiq.merge(size: 25) # Pool maior para o servidor
end

Sidekiq.configure_client do |config|
  config.redis = config_redis_sidekiq.merge(size: 10) # Pool adequado para o cliente
end