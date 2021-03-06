# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Lint do
  describe 'POST /ci/lint' do
    context 'with valid .gitlab-ci.yaml content' do
      let(:yaml_content) do
        File.read(Rails.root.join('spec/support/gitlab_stubs/gitlab_ci.yml'))
      end

      it 'passes validation' do
        post api('/ci/lint'), params: { content: yaml_content }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to be_an Hash
        expect(json_response['status']).to eq('valid')
        expect(json_response['errors']).to eq([])
      end

      it 'outputs expanded yaml content' do
        post api('/ci/lint'), params: { content: yaml_content, include_merged_yaml: true }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to have_key('merged_yaml')
      end
    end

    context 'with an invalid .gitlab_ci.yml' do
      context 'with invalid syntax' do
        let(:yaml_content) { 'invalid content' }

        it 'responds with errors about invalid syntax' do
          post api('/ci/lint'), params: { content: yaml_content }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['status']).to eq('invalid')
          expect(json_response['errors']).to eq(['Invalid configuration format'])
        end

        it 'outputs expanded yaml content' do
          post api('/ci/lint'), params: { content: yaml_content, include_merged_yaml: true }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to have_key('merged_yaml')
        end
      end

      context 'with invalid configuration' do
        let(:yaml_content) { '{ image: "ruby:2.7",  services: ["postgres"] }' }

        it 'responds with errors about invalid configuration' do
          post api('/ci/lint'), params: { content: yaml_content }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['status']).to eq('invalid')
          expect(json_response['errors']).to eq(['jobs config should contain at least one visible job'])
        end

        it 'outputs expanded yaml content' do
          post api('/ci/lint'), params: { content: yaml_content, include_merged_yaml: true }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to have_key('merged_yaml')
        end
      end
    end

    context 'without the content parameter' do
      it 'responds with validation error about missing content' do
        post api('/ci/lint')

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']).to eq('content is missing')
      end
    end
  end

  describe 'GET /projects/:id/ci/lint' do
    subject(:ci_lint) { get api("/projects/#{project.id}/ci/lint", api_user), params: { dry_run: dry_run } }

    let_it_be(:api_user) { create(:user) }
    let(:project) { create(:project, :repository) }
    let(:dry_run) { nil }

    RSpec.shared_examples 'valid config' do
      it 'passes validation' do
        ci_lint

        included_config = YAML.safe_load(included_content, [Symbol])
        root_config = YAML.safe_load(yaml_content, [Symbol])
        expected_yaml = included_config.merge(root_config).except(:include).to_yaml

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to be_an Hash
        expect(json_response['merged_yaml']).to eq(expected_yaml)
        expect(json_response['valid']).to eq(true)
        expect(json_response['errors']).to eq([])
      end
    end

    RSpec.shared_examples 'invalid config' do
      it 'responds with errors about invalid configuration' do
        ci_lint

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['merged_yaml']).to eq(yaml_content)
        expect(json_response['valid']).to eq(false)
        expect(json_response['errors']).to eq(['jobs config should contain at least one visible job'])
      end
    end

    context 'when unauthenticated' do
      it 'returns authentication error' do
        ci_lint

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when authenticated as project member' do
      before do
        project.add_developer(api_user)
      end

      context 'with valid .gitlab-ci.yml content' do
        let(:yaml_content) do
          { include: { local: 'another-gitlab-ci.yml' }, test: { stage: 'test', script: 'echo 1' } }.to_yaml
        end

        let(:included_content) do
          { another_test: { stage: 'test', script: 'echo 1' } }.to_yaml
        end

        before do
          project.repository.create_file(
            project.creator,
            '.gitlab-ci.yml',
            yaml_content,
            message: 'Automatically created .gitlab-ci.yml',
            branch_name: 'master'
          )

          project.repository.create_file(
            project.creator,
            'another-gitlab-ci.yml',
            included_content,
            message: 'Automatically created another-gitlab-ci.yml',
            branch_name: 'master'
          )
        end

        context 'when running as dry run' do
          let(:dry_run) { true }

          it_behaves_like 'valid config'
        end

        context 'when running static validation' do
          let(:dry_run) { false }

          it_behaves_like 'valid config'
        end
      end

      context 'with invalid .gitlab-ci.yml content' do
        let(:yaml_content) do
          { image: 'ruby:2.7', services: ['postgres'] }.to_yaml
        end

        before do
          stub_ci_pipeline_yaml_file(yaml_content)
        end

        context 'when running as dry run' do
          let(:dry_run) { true }

          it_behaves_like 'invalid config'
        end

        context 'when running static validation' do
          let(:dry_run) { false }

          it_behaves_like 'invalid config'
        end
      end
    end
  end
end
