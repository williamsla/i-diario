# frozen_string_literal: true

module AeeDetectable
  extend ActiveSupport::Concern

  def self.grade_aee?(grade)
    grade&.description.to_s.match?(/aee/i)
  end

  def self.classroom_aee?(classroom)
    Array(classroom&.grades).any? { |grade| grade_aee?(grade) }
  end
end
