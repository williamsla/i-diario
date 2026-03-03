# encoding: utf-8
class EntityLogoUploader < CarrierWave::Uploader::Base
  # Inclui o id da entidade (tenant) no caminho para que cada município
  # tenha sua própria pasta de logos quando a mesma app atende vários domínios.
  def store_dir
    base = "uploads/#{model.class.to_s.underscore}/#{mounted_as}"
    if Entity.current.present?
      "#{base}/entity_#{Entity.current.id}/#{model.id}"
    else
      "#{base}/#{model.id}"
    end
  end

  def extension_white_list
    %w(jpg jpeg gif png)
  end
end
