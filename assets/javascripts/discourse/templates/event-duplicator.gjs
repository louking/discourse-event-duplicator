import { on } from "@ember/modifier";
import EventDuplicatorReview from "../components/event-duplicator-review";
import { i18n } from "discourse-i18n";

export default <template>
  {{! Review/edit step: shown after picking a category+tags (series) or a
    single topic (topic-admin menu item). }}
  <div class="event-duplicator-page">
    <h2>{{i18n "event_duplicator.review.title" tags=@controller.tagsLabel}}</h2>

    <div class="control-group event-duplicator-date-strategy">
      <label>{{i18n "event_duplicator.review.date_strategy"}}</label>
      <select {{on "change" @controller.setDateStrategy}}>
        <option
          value="calendar_date"
          selected={{@controller.isCalendarDateStrategy}}
        >{{i18n "event_duplicator.date_strategy.calendar_date"}}</option>
        <option
          value="nth_weekday_of_month"
          selected={{@controller.isNthWeekdayOfMonthStrategy}}
        >{{i18n "event_duplicator.date_strategy.nth_weekday_of_month"}}</option>
      </select>
    </div>

    <EventDuplicatorReview
      @topics={{@model.topics}}
      @isDuplicating={{@controller.isDuplicating}}
      @onConfirm={{@controller.confirmDuplication}}
      @result={{@controller.result}}
    />

    {{#if @controller.result.skipped.length}}
      <div class="event-duplicator-result">
        <div class="alert alert-error">
          <p>{{i18n "event_duplicator.review.result.skipped_heading"}}</p>
          <ul>
            {{#each @controller.result.skipped as |entry|}}
              <li>
                {{entry.title}}:
                {{#if entry.existing_duplicate_topic_id}}
                  <a href={{entry.existing_duplicate_topic_url}}>{{i18n
                      "event_duplicator.review.duplicated_to_topic"
                    }}</a>
                {{else}}
                  {{entry.reason}}
                {{/if}}
              </li>
            {{/each}}
          </ul>
        </div>
      </div>
    {{/if}}
  </div>
</template>
