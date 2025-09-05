#!/bin/bash

sudo systemctl restart rails-server
sudo systemctl restart sidekiq-main
sudo systemctl restart sidekiq-sync
sudo systemctl restart sidekiq-exams