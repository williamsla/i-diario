class SyncTenantFeatureFlagsFromSecrets < ActiveRecord::Migration
  def up
    return unless column_exists?(:general_configurations, :semestral_recovery)

    secrets = Rails.application.secrets
    updates = {}

    if secrets_key?(secrets, :show_objectives)
      updates[:show_objectives] = truthy_secret?(secrets.show_objectives)
    end

    if secrets_key?(secrets, :semestral_recovery) || secrets_key?(secrets, :SEMESTRAL_RECOVERY)
      updates[:semestral_recovery] = truthy_secret?(secrets.semestral_recovery) ||
                                     truthy_secret?(secrets.SEMESTRAL_RECOVERY)
    end

    if secrets_key?(secrets, :conceptual_exam_batch_layout)
      updates[:conceptual_exam_batch_layout] = truthy_secret?(secrets.conceptual_exam_batch_layout)
    end

    return if updates.empty?

    GeneralConfiguration.reset_column_information
    GeneralConfiguration.update_all(updates)
  end

  def down
    # irreversível: valores já estavam no secrets legado
  end

  private

  def secrets_key?(secrets, key)
    secrets.respond_to?(key) && !secrets.public_send(key).nil?
  rescue NoMethodError
    false
  end

  def truthy_secret?(value)
    value == true || value.to_s.strip.casecmp('true').zero? || value.to_s == '1'
  end
end
