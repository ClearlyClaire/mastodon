# frozen_string_literal: true

class AnnualReport::Source
  attr_reader :account, :year

  def initialize(account, year)
    @account = account
    @year = year
  end

  protected

  def year_as_snowflake_range
    (beginning_snowflake_id..ending_snowflake_id)
  end

  private

  def beginning_snowflake_id
    Mastodon::Snowflake.id_at DateTime.new(year).beginning_of_year
  end

  def ending_snowflake_id
    Mastodon::Snowflake.id_at DateTime.new(year).end_of_year
  end
end
