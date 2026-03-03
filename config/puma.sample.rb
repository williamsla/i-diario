#!/usr/bin/env puma

# Min and Max threads per worker
# Workers = núcleos físicos (ou núcleos - 1 para deixar margem ao SO)
workers 2
threads 2, 5

preload_app!

environment "production"

bind "tcp://127.0.0.1:3000"

pidfile "tmp/pids/puma.pid"

stdout_redirect "log/puma.stdout.log", "log/puma.stderr.log", true
worker_timeout 60

on_worker_boot do
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Base.establish_connection
  end
end