#!/bin/bash
set -e

echo "Parando Sidekiq..."
sudo systemctl stop sidekiq-exams
sudo systemctl stop sidekiq-sync
sudo systemctl stop sidekiq-main

sleep 5

echo "Reiniciando Rails..."
sudo systemctl restart rails-server

sleep 5

echo "Subindo Sidekiq..."
sudo systemctl start sidekiq-main
sudo systemctl start sidekiq-sync
sudo systemctl start sidekiq-exams
