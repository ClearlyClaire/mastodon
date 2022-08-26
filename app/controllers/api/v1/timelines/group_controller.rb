# frozen_string_literal: true

class Api::V1::Timelines::GroupController < Api::BaseController
  include Authorization

  before_action -> { doorkeeper_authorize! :read, :'read:groups' } # TODO: do we really want a new scope?
  before_action :require_user!
  before_action :set_group
  before_action :set_statuses

  after_action :insert_pagination_headers, unless: -> { @statuses.empty? }

  def show
    render json: @statuses,
           each_serializer: REST::StatusSerializer,
           relationships: StatusRelationshipsPresenter.new(@statuses, current_user.account_id)
  end

  private

  def set_group
    @group = Group.find(params[:id])
    authorize @group, :show_posts?
  rescue Mastodon::NotPermittedError
    not_found
  end

  def set_statuses
    @statuses = cached_group_statuses
  end

  def cached_group_statuses
    cache_collection group_statuses, Status
  end

  def group_statuses
    group_feed.get(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params[:max_id],
      params[:since_id],
      params[:min_id]
    )
  end

  def group_feed
    GroupFeed.new(@group, current_account)
  end

  def insert_pagination_headers
    set_pagination_headers(next_path, prev_path)
  end

  def pagination_params(core_params)
    params.slice(:limit).permit(:limit).merge(core_params)
  end

  def next_path
    api_v1_timelines_list_url params[:id], pagination_params(max_id: pagination_max_id)
  end

  def prev_path
    api_v1_timelines_list_url params[:id], pagination_params(min_id: pagination_since_id)
  end

  def pagination_max_id
    @statuses.last.id
  end

  def pagination_since_id
    @statuses.first.id
  end
end
