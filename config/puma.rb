# frozen_string_literal: true

require "etc"

# Variáveis: omita RAILS_MAX_THREADS e WEB_CONCURRENCY para calcular com DATABASE_POOL e CPUs.
# Ver também config/puma.sample.rb (exemplo fixo para VM sem Docker).

def int_env(key)
  v = ENV[key]
  return nil if v.nil? || v.strip.empty?

  Integer(v)
rescue ArgumentError
  nil
end

cores = Etc.nprocessors.nonzero? || 1
pool = int_env("DATABASE_POOL") || 25

explicit_workers = int_env("WEB_CONCURRENCY")
explicit_threads = int_env("RAILS_MAX_THREADS")

workers_count =
  if explicit_workers.nil?
    if cores < 2 || pool < 4
      0
    else
      w = [cores, (pool / 4).floor, 8].min
      w = [w, 1].max
      (w * 2) > pool ? 0 : w
    end
  else
    explicit_workers
  end

threads_count =
  if explicit_threads.nil?
    if workers_count.zero?
      [[pool, 32].min, 2].max
    else
      t = pool / workers_count
      [[t, 2].max, 32].min
    end
  else
    explicit_threads
  end

if workers_count.positive?
  max_threads = [pool / workers_count, 1].max
  threads_count = [threads_count, max_threads].min
end

if workers_count.zero?
  threads_count = [threads_count, pool].min
end

workers workers_count
threads threads_count, threads_count

if ENV["PUMA_LOG_CONCURRENCY"] == "1"
  $stderr.puts(
    "[puma] cores=#{cores} DATABASE_POOL=#{pool} " \
    "WEB_CONCURRENCY=#{workers_count} RAILS_MAX_THREADS=#{threads_count}"
  )
end

bind "tcp://0.0.0.0:#{ENV.fetch("PORT", 3000)}"

environment ENV.fetch("RAILS_ENV", "development")

plugin :tmp_restart
