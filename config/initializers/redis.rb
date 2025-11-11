if Rails.application.secrets[:REDIS_MODE] == 'sentinel'
  # --- MODO SENTINEL ---
  config_redis_sidekiq = {
    url: "#{Rails.application.secrets[:REDIS_URL]}#{Rails.application.secrets[:REDIS_DB_SIDEKIQ]}",
    role: "master",
    sentinels: Rails.application.secrets[:REDIS_SENTINELS].split(";").map { |host| { host: host, port: 26379 } }
  }

else
  # --- MODO STANDALONE ---
  config_redis_sidekiq = {
    url: "#{Rails.application.secrets[:REDIS_URL]}#{Rails.application.secrets[:REDIS_DB_SIDEKIQ]}"
  }
end

# --- Redis padrão da aplicação (usado em sincronizações e jobs customizados) ---
$REDIS_DB = Redis.new(config_redis_sidekiq)

Sidekiq.configure_server do |config|
  config.redis = config_redis_sidekiq
end

Sidekiq.configure_client do |config|
  config.redis = config_redis_sidekiq
end
