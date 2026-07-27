import { on } from "@ember/modifier";
import CategoryChooser from "discourse/select-kit/components/category-chooser";
import TagChooser from "discourse/select-kit/components/tag-chooser";
import DButton from "discourse/ui-kit/d-button";
import { not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default <template>
  <div class="event-duplicator-new-page">
    <h2>{{i18n "event_duplicator.new.title"}}</h2>

    <div class="control-group">
      <label>{{i18n "event_duplicator.new.category"}}</label>
      <CategoryChooser
        @value={{@controller.categoryId}}
        @onChange={{@controller.setCategoryId}}
      />
    </div>

    <div class="control-group">
      <label>{{i18n "event_duplicator.new.tags"}}</label>
      <TagChooser
        @tags={{@controller.tags}}
        @categoryId={{@controller.categoryId}}
        @onChange={{@controller.setTags}}
      />
    </div>

    <div class="control-group">
      <label>{{i18n "event_duplicator.new.starts_after"}}</label>
      <div class="event-duplicator-date-field">
        <input
          type="date"
          value={{@controller.startsAfter}}
          {{on "change" @controller.setStartsAfter}}
        />
        {{#if @controller.startsAfter}}
          <DButton
            @action={{@controller.clearStartsAfter}}
            @label="event_duplicator.new.clear_date"
            @class="btn-flat"
          />
        {{/if}}
      </div>
    </div>

    <div class="control-group">
      <label>{{i18n "event_duplicator.new.starts_before"}}</label>
      <div class="event-duplicator-date-field">
        <input
          type="date"
          value={{@controller.startsBefore}}
          {{on "change" @controller.setStartsBefore}}
        />
        {{#if @controller.startsBefore}}
          <DButton
            @action={{@controller.clearStartsBefore}}
            @label="event_duplicator.new.clear_date"
            @class="btn-flat"
          />
        {{/if}}
      </div>
    </div>

    <DButton
      @class="btn-primary"
      @action={{@controller.proceed}}
      @disabled={{not @controller.canProceed}}
      @label="event_duplicator.new.next"
    />
  </div>
</template>
