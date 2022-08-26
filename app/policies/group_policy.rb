# frozen_string_literal: true

class GroupPolicy < ApplicationPolicy
  def show?
    true
  end

  def show_posts?
    true # TODO: add support for private groups?
  end

  def post?
    record.members.where(id: current_account&.id).exists?
  end
end
