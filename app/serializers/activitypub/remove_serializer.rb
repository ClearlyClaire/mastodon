# frozen_string_literal: true

class ActivityPub::RemoveSerializer < ActivityPub::Serializer
  include RoutingHelper

  attributes :type, :actor, :target
  attribute :proper_object, key: :object

  def type
    'Remove'
  end

  def actor
    instance_options[:actor].presence || ActivityPub::TagManager.instance.uri_for(object.account)
  end

  def proper_object
    ActivityPub::TagManager.instance.uri_for(object)
  end

  def target
    instance_options[:target].presence || account_collection_url(object.account, :featured)
  end
end
