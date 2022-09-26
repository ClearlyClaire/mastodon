require 'rails_helper'

describe GroupMembersController do
  render_views

  let(:group) { Fabricate(:group) }
  let(:account1) { Fabricate(:account) }
  let(:account2) { Fabricate(:account) }

  describe 'GET #index' do
    let!(:membership1) { group.memberships.create!(account: account1) }
    let!(:membership2) { group.memberships.create!(account: account2) }

    context 'when format is html' do
      subject(:response) { get :index, params: { group_id: group.id, format: :html } }

      context 'when the group is temporarily suspended' do
        before do
          group.suspend!
        end

        it 'returns http forbidden' do
          expect(response).to have_http_status(403)
        end
      end

      it 'assigns memberships' do
        expect(response).to have_http_status(200)

        assigned = assigns(:memberships).to_a
        expect(assigned.size).to eq 2
        expect(assigned[0]).to eq membership2
        expect(assigned[1]).to eq membership1
      end

      it 'does not assign blocked users' do
        user = Fabricate(:user)
        user.account.block!(account1)
        sign_in(user)

        expect(response).to have_http_status(200)

        assigned = assigns(:memberships).to_a
        expect(assigned.size).to eq 1
        expect(assigned[0]).to eq membership2
      end
    end

    context 'when format is json' do
      subject(:response) { get :index, params: { group_id: group.id, page: page, format: :json } }
      subject(:body) { JSON.parse(response.body) }

      context 'with page' do
        let(:page) { 1 }

        it 'returns members' do
          expect(response).to have_http_status(200)
          expect(body['totalItems']).to eq 2
          expect(body['partOf']).to be_present
        end

        context 'when the group is temporarily suspended' do
          before do
            group.suspend!
          end

          it 'returns http forbidden' do
            expect(response).to have_http_status(403)
          end
        end
      end

      context 'without page' do
        let(:page) { nil }

        it 'returns followers' do
          expect(response).to have_http_status(200)
          expect(body['totalItems']).to eq 2
          expect(body['partOf']).to be_blank
        end

        context 'when the group hides their members' do
          before do
            group.update(hide_members: true)
          end

          it 'returns followers count' do
            expect(body['totalItems']).to eq 2
          end

          it 'does not return items' do
            expect(body['items']).to be_blank
            expect(body['orderedItems']).to be_blank
            expect(body['first']).to be_blank
            expect(body['last']).to be_blank
          end
        end

        context 'when the group is temporarily suspended' do
          before do
            group.suspend!
          end

          it 'returns http forbidden' do
            expect(response).to have_http_status(403)
          end
        end
      end
    end
  end
end
