# frozen_string_literal: true

# Implemented according to HTTP signatures (Draft 6)
# <https://tools.ietf.org/html/draft-cavage-http-signatures-06>
module SignatureVerification
  extend ActiveSupport::Concern

  include DomainControlHelper

  EXPIRATION_WINDOW_LIMIT = 12.hours
  CLOCK_SKEW_MARGIN       = 1.hour

  class SignatureVerificationError < StandardError; end

  def require_signature!
    render plain: signature_verification_failure_reason, status: signature_verification_failure_code unless signed_request_account
  end

  def signed_request?
    request.headers['Signature'].present?
  end

  def signature_verification_failure_reason
    @signature_verification_failure_reason
  end

  def signature_verification_failure_code
    @signature_verification_failure_code || 401
  end

  def signature_key_id
    signature_params['keyId']
  end

  def signature_algorithm
    signature_params.fetch('algorithm', 'hs2019')
  end

  def signed_headers
    signature_params.fetch('headers', signature_algorithm == 'hs2019' ? '(created)' : 'date').downcase.split(' ')
  end

  def signature_params
    @signature_params ||= begin
      raw_signature    = request.headers['Signature']
      signature_params = {}

      # TODO: this is really approximative... we should fix it with proper parsing
      raw_signature.split(',').each do |part|
        parsed_parts = part.match(/([a-z]+)="([^"]+)"/i)
        next if parsed_parts.nil? || parsed_parts.size != 3
        signature_params[parsed_parts[1]] = parsed_parts[2]
      end

      signature_params
    end
  end

  def signed_request_account
    return @signed_request_account if defined?(@signed_request_account)

    raise SignatureVerificationError, 'Request not signed' unless signed_request?
    raise SignatureVerificationError, 'Incompatible request signature. keyId and signature are required' if missing_required_signature_parameters?
    raise SignatureVerificationError, 'Unsupported signature algorithm (only rsa-sha256 and hs2019 are supported)' unless %w(rsa-sha256 hs2019).include?(signature_algorithm)
    raise SignatureVerificationError, 'Signed request date outside acceptable time window' unless matches_time_window?

    account = account_from_key_id(signature_params['keyId'])

    raise SignatureVerificationError, "Public key not found for key #{signature_params['keyId']}" if account.nil?

    signature             = Base64.decode64(signature_params['signature'])
    compare_signed_string = build_signed_string

    return account unless verify_signature(account, signature, compare_signed_string).nil?

    account = stoplight_wrap_request { account.possibly_stale? ? account.refresh! : account_refresh_key(account) }

    raise SignatureVerificationError, "Public key not found for key #{signature_params['keyId']}" if account.nil?

    return account unless verify_signature(account, signature, compare_signed_string).nil?

    @signature_verification_failure_reason = "Verification failed for #{account.username}@#{account.domain} #{account.uri}"
    @signed_request_account = nil
  rescue SignatureVerificationError => e
    @signature_verification_failure_reason = e.message
    @signed_request_account = nil
  end

  def request_body
    @request_body ||= request.raw_post
  end

  private

  def verify_signature(account, signature, compare_signed_string)
    if account.keypair.public_key.verify(OpenSSL::Digest::SHA256.new, signature, compare_signed_string)
      @signed_request_account = account
      @signed_request_account
    end
  rescue OpenSSL::PKey::RSAError
    nil
  end

  def build_signed_string
    signed_headers.map do |signed_header|
      if signed_header == Request::REQUEST_TARGET
        "#{Request::REQUEST_TARGET}: #{request.method.downcase} #{request.path}"
      elsif signed_header == '(created)'
        raise SignatureVerificationError, 'Invalid pseudo-header (created) for rsa-sha256' unless signature_algorithm == 'hs2019'
        raise SignatureVerificationError, 'Pseudo-header (created) used but corresponding argument missing' if signature_params['created'].blank?

        "(created): #{signature_params['created']}"
      elsif signed_header == '(expires)'
        raise SignatureVerificationError, 'Invalid pseudo-header (expires) for rsa-sha256' unless signature_algorithm == 'hs2019'
        raise SignatureVerificationError, 'Pseudo-header (expires) used but corresponding argument missing' if signature_params['expires'].blank?

        "(expires): #{signature_params['expires']}"
      elsif signed_header == 'digest'
        "digest: #{body_digest}"
      else
        "#{signed_header}: #{request.headers[to_header_name(signed_header)]}"
      end
    end.join("\n")
  end

  def matches_time_window?
    created_time = nil
    expires_time = nil

    begin
      if signature_algorithm == 'hs2019' && signature_params['created'].present?
        created_time = Time.at(signature_params['created'].to_i).utc
      elsif request.headers['Date'].present?
        created_time = Time.httpdate(request.headers['Date']).utc
      end

      expires_time = Time.at(signature_params['expires'].to_i).utc if signature_params['expires'].present?
    rescue ArgumentError
      return false
    end

    expires_time ||= created_time + 5.minutes unless created_time.nil?
    expires_time = [expires_time, created_time + EXPIRATION_WINDOW_LIMIT].min unless created_time.nil?

    return false if created_time.present? && created_time > Time.now.utc + CLOCK_SKEW_MARGIN
    return false if expires_time.present? && Time.now.utc > expires_time + CLOCK_SKEW_MARGIN

    true
  end

  def body_digest
    "SHA-256=#{Digest::SHA256.base64digest(request_body)}"
  end

  def to_header_name(name)
    name.split(/-/).map(&:capitalize).join('-')
  end

  def missing_required_signature_parameters?
    signature_params['keyId'].blank? || signature_params['signature'].blank?
  end

  def account_from_key_id(key_id)
    domain = key_id.start_with?('acct:') ? key_id.split('@').last : key_id

    if domain_not_allowed?(domain)
      @signature_verification_failure_code = 403
      return
    end

    if key_id.start_with?('acct:')
      stoplight_wrap_request { ResolveAccountService.new.call(key_id.gsub(/\Aacct:/, '')) }
    elsif !ActivityPub::TagManager.instance.local_uri?(key_id)
      account   = ActivityPub::TagManager.instance.uri_to_resource(key_id, Account)
      account ||= stoplight_wrap_request { ActivityPub::FetchRemoteKeyService.new.call(key_id, id: false) }
      account
    end
  rescue Mastodon::HostValidationError
    nil
  end

  def stoplight_wrap_request(&block)
    Stoplight("source:#{request.remote_ip}", &block)
      .with_fallback { nil }
      .with_threshold(1)
      .with_cool_off_time(5.minutes.seconds)
      .with_error_handler { |error, handle| error.is_a?(HTTP::Error) || error.is_a?(OpenSSL::SSL::SSLError) ? handle.call(error) : raise(error) }
      .run
  end

  def account_refresh_key(account)
    return if account.local? || !account.activitypub?
    ActivityPub::FetchRemoteAccountService.new.call(account.uri, only_key: true)
  end
end
