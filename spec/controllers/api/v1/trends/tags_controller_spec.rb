# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Trends::TagsController, type: :controller do
  render_views

  # TODO: return "actually" trending tags that are not the always trending tags
  # TODO: this is WET
  describe 'GET #index' do
    let(:forced_tags) { Fabricate.times(10, :tag) }

    it 'returns http success' do
      get :index
      expect(response).to have_http_status(200)
    end

    context 'with always trending tags' do
      before do
        forced_tags_relation = forced_tags.reduce(Tag.where(id: -1)) { |relation, forced_tag| relation.or(Tag.where(name: forced_tag.name)) }
        allow(controller).to receive(:always_trending).and_return(forced_tags_relation)
      end

      context 'with fewer tags always trending than the limit parameter' do
        before do
          get :index, params: { limit: 11 }
        end

        it 'returns http success' do
          expect(response).to have_http_status(200)
        end

        it 'respects the limit parameter' do
          expect(response).to have_http_status(200)
          expect(JSON.parse(response.body).size).to be <= 11
        end

        it 'responds with all always trending tags' do
          response_tags = JSON.parse(response.body)
          expect(forced_tags.all? { |forced_tag| response_tags.any? { |response_tag| forced_tag.name == response_tag['name'] } }).to be true
        end
      end

      context 'with more tags always trending than the limit parameter' do
        before do
          get :index, params: { limit: 2 }
        end

        it 'overrides the limit parameter' do
          expect(response).to have_http_status(200)
          expect(JSON.parse(response.body).size).to eq(forced_tags.size)
        end

        it 'responds with only always trending tags' do
          response_tags = JSON.parse(response.body)
          expect(response_tags.all? { |response_tag| forced_tags.any? { |forced_tag| response_tag['name'] == forced_tag.name } }).to be true
        end
      end
    end
  end
end
