# frozen_string_literal: true

module AvaliationBatchGrades
  # Remove avaliação numérica da etapa apagando diários de avaliação (e notas) em transação.
  class DestroyColumnService
    attr_reader :error

    def initialize(avaliation:)
      @avaliation = avaliation
      @error = nil
    end

    def call
      @error = nil
      ActiveRecord::Base.transaction do
        @avaliation.daily_notes.reload.each do |dn|
          unless dn.destroy
            @error = dn.errors.full_messages.join('; ')
            raise ActiveRecord::Rollback
          end
        end
        @avaliation.reload
        @avaliation.destroy
        unless @avaliation.destroyed?
          @error = @avaliation.errors.full_messages.join('; ')
          raise ActiveRecord::Rollback
        end
      end
      return false if @error.present?

      true
    rescue StandardError => e
      Rails.logger.error("[AvaliationBatchGrades::DestroyColumnService] #{e.class}: #{e.message}")
      @error ||= e.message
      false
    end
  end
end
