# frozen_string_literal: true

class PostStatusService < BaseService
  include Redisable
  include LanguagesHelper

  MIN_SCHEDULE_OFFSET = 5.minutes.freeze

  # Validate and, if appropriate, post or schedule a text status update,
  # fetching and notifying any mentioned remote users. If the new status is
  # in reply to an account the user is not already following, make a note of
  # that for account recommendation purposes.
  #
  # @note It is invalid to create a post with media attachments and a poll at
  #   the same time.
  #
  # @note Attempting to schedule a status in the past will simply post the
  #   status immediately.
  #
  # @note This is undocumented in the upstream API documentation, but
  #   attempting to create a status with limited visibility is allowed.
  #   That is to say, sending a POST request to the status creation endpoint
  #   with the visibility attribute set to "limited" will create a status
  #   with the (undocumented) "limited" visibility! The implication of this
  #   are nonobvious, and, frankly, not at all useful; see {Status#visibility}
  #   for the details.
  #
  # @param [Account] account Account from which to post
  # @param [Hash] options Options hash
  # @option options [String] :text Message to post. Defaults to the empty
  #   string, unless there is nonblank spoiler text, in which case a single
  #   period is used for text posts, or an appropriate emoji for media
  # @option options [Status] :thread Optional status to reply to
  # @option options [Boolean] :sensitive Optional; forced to true if
  #   spoiler_text is present. Defaults to the user's default post sensitivity
  #   setting
  # @option options [String] :visibility Optional; if present, SHOULD be one of
  #   "public", "unlisted", "private", or "direct", but see {Status#visibility}.
  #   Defaults to the user's default post privacy.
  # @option options [String] :spoiler_text Optional content warning
  # @option options [String] :language Optional two-letter language code. If
  #   blank, invalid, or unknown to the backend, defaults to the user's default
  #   post language if it exists, and then to the default locale
  # @option options [String] :scheduled_at Optional; if present, should be a
  #   valid timestamp, and should refer to a time at least {MIN_SCHEDULE_OFFSET}
  #   into the future. (If determined to be scheduled in the past, the status
  #   will be created immediately!)
  # @option options [Hash] :poll Optional poll to attach. Invalid to be present
  #   when media attachments are also present
  # @option options [Enumerable] :media_ids Optional array of media IDs to
  #   attach. Invalid to be present when a poll is also present
  # @option options [Doorkeeper::Application] :application Optional application
  #   the status was posted from
  # @option options [String] :idempotency Optional idempotency key, preventing
  #   this status from being created if a status with this key already exists
  # @option options [Boolean] :with_rate_limit Strictly optional, but should be
  #   forced to true inside a controller. Can be safely ignored if, for
  #   example, creating a status as part of a test
  # @return [Status]
  def call(account, options = {})
    @account     = account
    @options     = options
    @text        = @options[:text] || ''
    @in_reply_to = @options[:thread]

    return idempotency_duplicate if idempotency_given? && idempotency_duplicate?

    validate_media!
    preprocess_attributes!

    if scheduled?
      schedule_status!
    else
      process_status!
      postprocess_status!
      bump_potential_friendship!
    end

    redis.setex(idempotency_key, 3_600, @status.id) if idempotency_given?

    @status
  end

  private

  def preprocess_attributes!
    if @text.blank? && @options[:spoiler_text].present?
     @text = '.'
     if @media&.find(&:video?) || @media&.find(&:gifv?)
       @text = '📹'
     elsif @media&.find(&:audio?)
       @text = '🎵'
     elsif @media&.find(&:image?)
       @text = '🖼'
     end
    end
    @sensitive    = (@options[:sensitive].nil? ? @account.user&.setting_default_sensitive : @options[:sensitive]) || @options[:spoiler_text].present?

    if !visibility_valid?
      raise Mastodon::ValidationError, I18n.t('statuses.validations.visibility', visibility: @options[:visibility])
    end

    @visibility   = @options[:visibility] || @account.user&.setting_default_privacy
    @visibility   = :unlisted if @visibility&.to_sym == :public && @account.silenced?
    @scheduled_at = @options[:scheduled_at]&.to_datetime
    @scheduled_at = nil if scheduled_in_the_past?
  rescue ArgumentError
    raise Mastodon::ValidationError, I18n.t('statuses.validations.scheduled_at', datetime: @options[:scheduled_at])
  end

  def process_status!
    # The following transaction block is needed to wrap the UPDATEs to
    # the media attachments when the status is created

    ApplicationRecord.transaction do
      @status = @account.statuses.create!(status_attributes)
    end

    process_hashtags_service.call(@status)
    process_mentions_service.call(@status)
  end

  def schedule_status!
    status_for_validation = @account.statuses.build(status_attributes)

    if status_for_validation.valid?
      # Marking the status as destroyed is necessary to prevent the status from being
      # persisted when the associated media attachments get updated when creating the
      # scheduled status.
      status_for_validation.destroy

      # The following transaction block is needed to wrap the UPDATEs to
      # the media attachments when the scheduled status is created

      ApplicationRecord.transaction do
        @status = @account.scheduled_statuses.create!(scheduled_status_attributes)
      end
    else
      raise ActiveRecord::RecordInvalid
    end
  end

  def postprocess_status!
    Trends.tags.register(@status)
    LinkCrawlWorker.perform_async(@status.id)
    DistributionWorker.perform_async(@status.id)
    ActivityPub::DistributionWorker.perform_async(@status.id) unless @status.local_only?
    PollExpirationNotifyWorker.perform_at(@status.poll.expires_at, @status.poll.id) if @status.poll
  end

  def validate_media!
    if @options[:media_ids].blank? || !@options[:media_ids].is_a?(Enumerable)
      @media = []
      return
    end

    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.poll') if @options[:poll].present?
    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many') if @options[:media_ids].size > 4

    @media = @account.media_attachments.where(status_id: nil).where(id: @options[:media_ids].take(4).map(&:to_i))

    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.images_and_video') if @media.size > 1 && @media.find(&:audio_or_video?)
    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.not_ready') if @media.any?(&:not_processed?)
  end

  def process_mentions_service
    ProcessMentionsService.new
  end

  def process_hashtags_service
    ProcessHashtagsService.new
  end

  def scheduled?
    @scheduled_at.present?
  end

  def idempotency_key
    "idempotency:status:#{@account.id}:#{@options[:idempotency]}"
  end

  def idempotency_given?
    @options[:idempotency].present?
  end

  def idempotency_duplicate
    if scheduled?
      @account.schedule_statuses.find(@idempotency_duplicate)
    else
      @account.statuses.find(@idempotency_duplicate)
    end
  end

  def idempotency_duplicate?
    @idempotency_duplicate = redis.get(idempotency_key)
  end

  def scheduled_in_the_past?
    @scheduled_at.present? && @scheduled_at <= Time.now.utc + MIN_SCHEDULE_OFFSET
  end

  # If the status was made in reply to an account the user is not already
  # following, increase the number of recorded interactions that user has had
  # with the author of the replied status, for account recommendation purposes.
  # @return void
  def bump_potential_friendship!
    return if !@status.reply? || @account.id == @status.in_reply_to_account_id
    ActivityTracker.increment('activity:interactions')
    return if @account.following?(@status.in_reply_to_account_id)
    PotentialFriendshipTracker.record(@account.id, @status.in_reply_to_account_id, :reply)
  end

  def status_attributes
    {
      text: @text,
      media_attachments: @media || [],
      ordered_media_attachment_ids: (@options[:media_ids] || []).map(&:to_i) & @media.map(&:id),
      thread: @in_reply_to,
      poll_attributes: poll_attributes,
      sensitive: @sensitive,
      spoiler_text: @options[:spoiler_text] || '',
      visibility: @visibility,
      language: valid_locale_cascade(@options[:language], @account.user&.preferred_posting_language, I18n.default_locale),
      application: @options[:application],
      content_type: @options[:content_type] || @account.user&.setting_default_content_type,
      rate_limit: @options[:with_rate_limit],
    }.compact
  end

  def scheduled_status_attributes
    {
      scheduled_at: @scheduled_at,
      media_attachments: @media || [],
      params: scheduled_options,
    }
  end

  def poll_attributes
    return if @options[:poll].blank?

    @options[:poll].merge(account: @account, voters_count: 0)
  end

  def scheduled_options
    @options.tap do |options_hash|
      options_hash[:in_reply_to_id]  = options_hash.delete(:thread)&.id
      options_hash[:application_id]  = options_hash.delete(:application)&.id
      options_hash[:scheduled_at]    = nil
      options_hash[:idempotency]     = nil
      options_hash[:with_rate_limit] = false
    end
  end

  # If a visibility is present in the options hash, ensure it represents a
  # proper status visibility
  # @example Behaviors that are implicitly specified by Mastodon
  #   @options[:visibility] = nil; visibility_vaild?              # => true
  #   @options[:visibility] = ""; visibility_vaild?               # => true
  #   @options[:visibility] = "         "; visibility_vaild?      # => true
  #   @options[:visibility] = "antohusathue"; visibility_invalid? # => true
  #   @options[:visibility] = "limited"; visibility_vaild?        # => true
  # @return [Boolean]
  def visibility_valid?
    @options[:visibility].nil? || @options[:visibility].blank? || Status.visibilities.key?(@options[:visibility])
  end
end
