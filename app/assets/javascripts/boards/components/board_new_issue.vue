<script>
import $ from 'jquery';
import { mapActions, mapGetters } from 'vuex';
import { GlButton } from '@gitlab/ui';
import { getMilestone } from 'ee_else_ce/boards/boards_util';
import ListIssue from 'ee_else_ce/boards/models/issue';
import eventHub from '../eventhub';
import ProjectSelect from './project_select.vue';
import boardsStore from '../stores/boards_store';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';

export default {
  name: 'BoardNewIssue',
  components: {
    ProjectSelect,
    GlButton,
  },
  mixins: [glFeatureFlagMixin()],
  props: {
    list: {
      type: Object,
      required: true,
    },
  },
  inject: {
    groupId: {
      type: Number,
    },
  },
  data() {
    return {
      title: '',
      error: false,
      selectedProject: {},
    };
  },
  computed: {
    ...mapGetters(['isSwimlanesOn']),
    disabled() {
      if (this.groupId) {
        return this.title === '' || !this.selectedProject.name;
      }
      return this.title === '';
    },
    shouldDisplaySwimlanes() {
      return this.glFeatures.boardsWithSwimlanes && this.isSwimlanesOn;
    },
  },
  mounted() {
    this.$refs.input.focus();
    eventHub.$on('setSelectedProject', this.setSelectedProject);
  },
  methods: {
    ...mapActions(['addListIssue', 'addListIssueFailure']),
    submit(e) {
      e.preventDefault();
      if (this.title.trim() === '') return Promise.resolve();

      this.error = false;

      const labels = this.list.label ? [this.list.label] : [];
      const assignees = this.list.assignee ? [this.list.assignee] : [];
      const milestone = getMilestone(this.list);

      const { weightFeatureAvailable } = boardsStore;
      const { weight } = weightFeatureAvailable ? boardsStore.state.currentBoard : {};

      const issue = new ListIssue({
        title: this.title,
        labels,
        subscribed: true,
        assignees,
        milestone,
        project_id: this.selectedProject.id,
        weight,
      });

      eventHub.$emit(`scroll-board-list-${this.list.id}`);
      this.cancel();

      if (this.shouldDisplaySwimlanes || this.glFeatures.graphqlBoardLists) {
        this.addListIssue({ list: this.list, issue, position: 0 });
      }

      return this.list
        .newIssue(issue)
        .then(() => {
          // Need this because our jQuery very kindly disables buttons on ALL form submissions
          $(this.$refs.submitButton).enable();

          if (!this.shouldDisplaySwimlanes && !this.glFeatures.graphqlBoardLists) {
            boardsStore.setIssueDetail(issue);
            boardsStore.setListDetail(this.list);
          }
        })
        .catch(() => {
          // Need this because our jQuery very kindly disables buttons on ALL form submissions
          $(this.$refs.submitButton).enable();

          // Remove the issue
          if (this.shouldDisplaySwimlanes || this.glFeatures.graphqlBoardLists) {
            this.addListIssueFailure({ list: this.list, issue });
          } else {
            this.list.removeIssue(issue);
          }

          // Show error message
          this.error = true;
        });
    },
    cancel() {
      this.title = '';
      eventHub.$emit(`toggle-issue-form-${this.list.id}`);
    },
    setSelectedProject(selectedProject) {
      this.selectedProject = selectedProject;
    },
  },
};
</script>

<template>
  <div class="board-new-issue-form">
    <div class="board-card position-relative p-3 rounded">
      <form @submit="submit($event)">
        <div v-if="error" class="flash-container">
          <div class="flash-alert">{{ __('An error occurred. Please try again.') }}</div>
        </div>
        <label :for="list.id + '-title'" class="label-bold">{{ __('Title') }}</label>
        <input
          :id="list.id + '-title'"
          ref="input"
          v-model="title"
          class="form-control"
          type="text"
          name="issue_title"
          autocomplete="off"
        />
        <project-select v-if="groupId" :group-id="groupId" :list="list" />
        <div class="clearfix gl-mt-3">
          <gl-button
            ref="submitButton"
            :disabled="disabled"
            class="float-left"
            variant="success"
            category="primary"
            type="submit"
            >{{ __('Submit issue') }}</gl-button
          >
          <gl-button
            ref="cancelButton"
            class="float-right"
            type="button"
            variant="default"
            @click="cancel"
            >{{ __('Cancel') }}</gl-button
          >
        </div>
      </form>
    </div>
  </div>
</template>
