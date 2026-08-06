# frozen_string_literal: true

module EducaMais
  module JwtToken
    ALGORITHM = 'HS256'

    module_function

    def encode(payload, secret:)
      raise ArgumentError, 'secret ausente' if secret.blank?

      header = Base64.urlsafe_encode64({ alg: ALGORITHM, typ: 'JWT' }.to_json).delete('=')
      body = Base64.urlsafe_encode64(payload.to_json).delete('=')
      signature = sign("#{header}.#{body}", secret)
      "#{header}.#{body}.#{signature}"
    end

    def decode(token, secret:)
      raise ArgumentError, 'secret ausente' if secret.blank?

      header, body, signature = token.to_s.split('.')
      return if header.blank? || body.blank? || signature.blank?

      expected = sign("#{header}.#{body}", secret)
      return unless secure_compare(signature, expected)

      payload = JSON.parse(Base64.urlsafe_decode64(pad_base64(body)))
      return if payload['exp'].present? && Time.zone.at(payload['exp'].to_i) < Time.zone.now

      payload.with_indifferent_access
    rescue JSON::ParserError
      nil
    end

    def sign(data, secret)
      Base64.urlsafe_encode64(
        OpenSSL::HMAC.digest('SHA256', secret, data)
      ).delete('=')
    end

    def secure_compare(a, b)
      return false if a.blank? || b.blank? || a.bytesize != b.bytesize

      l = a.unpack("C#{a.bytesize}")
      r = 0
      b.each_byte { |byte| r |= l.shift ^ byte }
      r.zero?
    end

    def pad_base64(value)
      value + ('=' * ((4 - value.length % 4) % 4))
    end
  end
end
