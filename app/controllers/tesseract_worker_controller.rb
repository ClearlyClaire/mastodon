# frozen_string_literal: true

class TesseractWorkerController < ActionController::Base
  include RoutingHelper

  content_security_policy do |p|
    base_host = Rails.configuration.x.web_domain

    assets_host   = Rails.configuration.action_controller.asset_host
    assets_host ||= host_to_url(base_host)

    media_host   = host_to_url(ENV['S3_ALIAS_HOST'])
    media_host ||= host_to_url(ENV['S3_CLOUDFRONT_HOST'])
    media_host ||= host_to_url(ENV['S3_HOSTNAME']) if ENV['S3_ENABLED'] == 'true'
    media_host ||= assets_host

    p.connect_src :self, :data, :blob, assets_host, media_host
  end

  def show
    expires_in 3.days, public: true

    base_host = Rails.configuration.x.web_domain

    assets_host   = Rails.configuration.action_controller.asset_host
    assets_host ||= host_to_url(base_host)

    render :text => "importScripts('#{assetHost}/packs/ocr/tesseract-core.wasm.js')", :content_type => "text/javascript"
  end
end

