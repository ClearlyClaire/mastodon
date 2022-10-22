# frozen_string_literal: true

class JoinGroupService < BaseService
  include Redisable
  include Payloadable
  include DomainControlHelper

  # @param [Account] account Account from which to join
  # @param [Group] Group to join
  def call(account, group)
    @account = account
    @group   = group

    raise ActiveRecord::RecordNotFound if joining_not_possible?
    raise Mastodon::NotPermittedError  if joining_not_allowed?

    if @group.locked? || @account.silenced? || !@group.local?
      request_join!
    elsif @group.local?
      direct_join!
    end
  end

  private

  def joining_not_possible?
    @group.nil? || @group.suspended?
  end

  def joining_not_allowed?
    domain_not_allowed?(@group.domain) || @group.blocking?(@account) || @account.domain_blocking?(@group.domain)
  end

  def request_join!
    membership_request = @group.membership_requests.create!(account: @account)

    if @group.local?
      # TODO: notifications
    else
      # TODO: federation
    end

    membership_request
  end

  def direct_join!
    membership = @group.memberships.create!(account: @account)

    # TODO: notifications

    membership
  end
end
