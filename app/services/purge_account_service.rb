# frozen_string_literal: true

class PurgeAccountService < BaseService
  include Payloadable

  ASSOCIATIONS_ON_SUSPEND = %w(
    account_notes
    account_pins
    active_relationships
    aliases
    block_relationships
    blocked_by_relationships
    conversation_mutes
    conversations
    custom_filters
    devices
    domain_blocks
    featured_tags
    follow_requests
    list_accounts
    migrations
    mute_relationships
    muted_by_relationships
    notifications
    owned_lists
    passive_relationships
    report_notes
    scheduled_statuses
    status_pins
  ).freeze

  # The following associations have no important side-effects
  # in callbacks and all of their own associations are secured
  # by foreign keys, making them safe to delete without loading
  # into memory
  ASSOCIATIONS_WITHOUT_SIDE_EFFECTS = %w(
    account_notes
    account_pins
    aliases
    conversation_mutes
    conversations
    custom_filters
    devices
    domain_blocks
    featured_tags
    follow_requests
    list_accounts
    migrations
    mute_relationships
    muted_by_relationships
    notifications
    owned_lists
    scheduled_statuses
    status_pins
  )

  ASSOCIATIONS_ON_DESTROY = %w(
    reports
    targeted_moderation_notes
    targeted_reports
  ).freeze

  # Suspend or remove an account and remove as much of its data
  # as possible. If it's a local account and it has not been confirmed
  # or never been approved, then side effects are skipped and both
  # the user and account records are removed fully. Otherwise,
  # it is controlled by options.
  # @param [Account]
  # @param [Hash] options
  # @option [Boolean] :reserve_username Keep account record
  # @option [Boolean] :skip_side_effects Side effects are ActivityPub and streaming API payloads
  def call(account, **options)
    @account = account
    @options = { reserve_username: true }.merge(options)

    if @account.local? && @account.user_unconfirmed_or_pending?
      @options[:reserve_username]  = false
      @options[:skip_side_effects] = true
    end

    purge_content!
  end

  private

  def purge_content!
    purge_statuses!
    purge_mentions!
    nullify_in_reply_to_account_id!
    purge_media_attachments!
    purge_polls!
    purge_generated_notifications!
    purge_favourites!
    purge_bookmarks!
    purge_feeds!
    purge_other_associations!

    @account.destroy unless keep_account_record?
  end

  def purge_statuses!
    @account.statuses.reorder(nil).where.not(id: reported_status_ids).in_batches do |statuses|
      BatchedRemoveStatusService.new.call(statuses, skip_side_effects: skip_side_effects?)
    end
  end

  def purge_mentions!
    @account.mentions.reorder(nil).where.not(status_id: reported_status_ids).in_batches.delete_all
  end

  def nullify_in_reply_to_account_id!
    Status.where(in_reply_to_account_id: @account.id).in_batches.update_all(in_reply_to_account_id: nil)
  end

  def purge_media_attachments!
    @account.media_attachments.reorder(nil).find_each do |media_attachment|
      next if keep_account_record? && reported_status_ids.include?(media_attachment.status_id)

      media_attachment.destroy
    end
  end

  def purge_polls!
    @account.polls.reorder(nil).where.not(status_id: reported_status_ids).in_batches.delete_all
  end

  def purge_generated_notifications!
    # By deleting polls and statuses without callbacks, we've left behind
    # polymorphically associated notifications generated by this account

    Notification.where(from_account: @account).in_batches.delete_all
  end

  def purge_favourites!
    @account.favourites.in_batches do |favourites|
      ids = favourites.pluck(:status_id)
      StatusStat.where(status_id: ids).update_all('favourites_count = GREATEST(0, favourites_count - 1)')
      Chewy.strategy.current.update(StatusesIndex, ids) if Chewy.enabled?
      Rails.cache.delete_multi(ids.map { |id| "statuses/#{id}" })
      favourites.delete_all
    end
  end

  def purge_bookmarks!
    @account.bookmarks.in_batches do |bookmarks|
      Chewy.strategy.current.update(StatusesIndex, bookmarks.pluck(:status_id)) if Chewy.enabled?
      bookmarks.delete_all
    end
  end

  def purge_other_associations!
    associations_for_destruction.each do |association_name|
      purge_association(association_name)
    end
  end

  def purge_feeds!
    return unless @account.local?

    FeedManager.instance.clean_feeds!(:home, [@account.id])
    FeedManager.instance.clean_feeds!(:list, @account.owned_lists.pluck(:id))
  end

  def purge_association(association_name)
    association = @account.public_send(association_name)

    if ASSOCIATIONS_WITHOUT_SIDE_EFFECTS.include?(association_name)
      association.in_batches.delete_all
    else
      association.in_batches.destroy_all
    end
  end

  def reported_status_ids
    @reported_status_ids ||= Report.where(target_account: @account).unresolved.pluck(:status_ids).flatten.uniq
  end

  def associations_for_destruction
    if keep_account_record?
      ASSOCIATIONS_ON_SUSPEND
    else
      ASSOCIATIONS_ON_SUSPEND + ASSOCIATIONS_ON_DESTROY
    end
  end

  def keep_account_record?
    @options[:reserve_username]
  end

  def skip_side_effects?
    @options[:skip_side_effects]
  end
end
