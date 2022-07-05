# frozen_string_literal: true

class Api::V1::Trends::TagsController < Api::BaseController
  before_action :set_tags

  after_action :insert_pagination_headers

  DEFAULT_TAGS_LIMIT = 10

  def index
    render json: @tags, each_serializer: REST::TagSerializer
  end

  private

  def enabled?
    Setting.trends
  end

  # Retrieve a comma-separated list of tags from the environment variable
  # `ALWAYS_TRENDING_TAGS`, which will always be reported as trending by
  # {#index}.
  #
  # `ALWAYS_TRENDING_TAGS` ought to match something like
  # `/^(?:[^[:space]]+,)*[^[:space]]+,?$/i`, but we do not (yet?) enforce
  # this. `ALWAYS_TRENDING_TAGS=Lune,Yuki,Baron,` is parsed as
  # `['Lune', 'Yuki', 'Baron']`, the same as without the final comma.
  #
  # @return [ActiveRecord::Relation] The tags that will always be trending
  def always_trending
    # TODO: do we need to sanitize ALWAYS_TRENDING_TAGS?
    # TODO: should we log when ALWAYS_TRENDING_TAGS includes a tag that does not exist?
    # TODO: can we get the empty Relation without searching for (what we hope is) an impossible id?
    ENV['ALWAYS_TRENDING_TAGS'].to_s.split(',')
                                    .reduce(Tag.none) { |relation, tag_name| relation.or(Tag.where(name: tag_name)) }
  end

  # Determine the tags that will be reported as trending, overriding the
  # `limit` param if {#always_trending} renders it necessary.
  #
  # Note that having too many tags always trending will render {#index}
  # completely deterministic (as per {#BaseController::limit_param})!
  # TODO: is that desirable? should we log a warning in that case?

  def set_tags
    @tags = if !enabled?
              []
            else
              guaranteed_tags              = always_trending
              # TODO: how does the query handle negative limits? is this necessary?
              limit_considering_guaranteed = [0, limit_param(DEFAULT_TAGS_LIMIT) - guaranteed_tags.size].max

              guaranteed_tags | tags_from_trends.offset(offset_param).limit(limit_considering_guaranteed)
            end
  end

  def tags_from_trends
    Trends.tags.query.allowed
  end

  def insert_pagination_headers
    set_pagination_headers(next_path, prev_path)
  end

  def pagination_params(core_params)
    params.slice(:limit).permit(:limit).merge(core_params)
  end

  def next_path
    api_v1_trends_tags_url pagination_params(offset: offset_param + limit_param(DEFAULT_TAGS_LIMIT)) if records_continue?
  end

  def prev_path
    api_v1_trends_tags_url pagination_params(offset: offset_param - limit_param(DEFAULT_TAGS_LIMIT)) if offset_param > limit_param(DEFAULT_TAGS_LIMIT)
  end

  def offset_param
    params[:offset].to_i
  end

  def records_continue?
    @tags.size == limit_param(DEFAULT_TAGS_LIMIT)
  end
end
