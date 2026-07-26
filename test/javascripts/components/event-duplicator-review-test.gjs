import { click, fillIn, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import EventDuplicatorReview from "discourse/plugins/discourse-event-duplicator/discourse/components/event-duplicator-review";

function topic(overrides = {}) {
  return {
    id: 1,
    title: "Grand Prix",
    original_start: "2026-07-04T18:00:00.000Z",
    original_end: "2026-07-04T20:00:00.000Z",
    proposed_start: "2027-07-04T18:00:00.000Z",
    proposed_end: "2027-07-04T20:00:00.000Z",
    already_duplicated: false,
    existing_duplicate_topic_id: null,
    existing_duplicate_topic_url: null,
    selected: true,
    ...overrides,
  };
}

module("Component | event-duplicator-review", function (hooks) {
  setupRenderingTest(hooks);

  test("shows a read-only old start and an editable new start, at day granularity", async function (assert) {
    this.topics = [topic()];

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
        />
      </template>
    );

    assert.dom("td:nth-child(3)").hasText("2026-07-04");
    assert.dom("input[type=date]").hasValue("2027-07-04");
  });

  test("editing the new-start date preserves the original time-of-day", async function (assert) {
    this.topics = [topic()];
    this.onConfirm = sinon.spy();

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
          @onConfirm={{this.onConfirm}}
        />
      </template>
    );

    await fillIn("input[type=date]", "2027-08-15");
    await click(".btn-primary");

    const [selectedItems] = this.onConfirm.firstCall.args;
    assert.strictEqual(
      selectedItems[0].startsAt,
      "2027-08-15T18:00:00.000Z",
      "date portion changed, time-of-day untouched"
    );
  });

  test("a manually-edited row keeps its edit when the proposal set changes identity (date-rule switch), an untouched row adopts the new proposal", async function (assert) {
    this.topics = [
      topic({ id: 1, proposed_start: "2027-07-04T18:00:00.000Z" }),
      topic({ id: 2, proposed_start: "2027-07-11T18:00:00.000Z" }),
    ];

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
        />
      </template>
    );

    const dateInputs = () => [...document.querySelectorAll("input[type=date]")];
    await fillIn(dateInputs()[0], "2027-09-01");

    // Simulate the route recomputing proposed dates after the reviewer picks
    // a different date strategy -- a brand new topics array/objects, as the
    // real route's model() produces. Reassigned via `this.set` (not plain
    // property assignment) -- the render-test context only notifies Ember's
    // rendering system of the change through `.set()`.
    this.set("topics", [
      topic({ id: 1, proposed_start: "2027-10-10T18:00:00.000Z" }),
      topic({ id: 2, proposed_start: "2027-10-17T18:00:00.000Z" }),
    ]);
    await settled();

    assert.strictEqual(
      dateInputs()[0].value,
      "2027-09-01",
      "row 1 keeps the reviewer's manual edit"
    );
    assert.strictEqual(
      dateInputs()[1].value,
      "2027-10-17",
      "row 2 (never touched) adopts the new proposed date"
    );
  });

  test("header checkbox in the selection column selects/clears every row", async function (assert) {
    this.topics = [
      topic({ id: 1, selected: false }),
      topic({ id: 2, selected: false }),
    ];

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
        />
      </template>
    );

    const selectionCheckboxes = () => [
      ...document.querySelectorAll(
        "tbody tr td:first-child input[type=checkbox]"
      ),
    ];
    const selectAllHeaderCheckbox = () =>
      document.querySelector("thead tr th:first-child input[type=checkbox]");

    assert.true(selectionCheckboxes().every((box) => !box.checked));

    await click(selectAllHeaderCheckbox());
    assert.true(selectionCheckboxes().every((box) => box.checked));

    await click(selectAllHeaderCheckbox());
    assert.true(selectionCheckboxes().every((box) => !box.checked));
  });

  test("header checkbox in the Date TBD column selects/clears every row's TBD flag", async function (assert) {
    this.topics = [topic({ id: 1 }), topic({ id: 2 })];

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
        />
      </template>
    );

    const tbdCheckboxes = () => [
      ...document.querySelectorAll(
        "tbody tr td:last-child input[type=checkbox]"
      ),
    ];
    const tbdHeaderCheckbox = () =>
      document.querySelector("thead tr th:last-child input[type=checkbox]");

    assert.true(
      tbdCheckboxes().every((box) => box.checked),
      "TBD defaults on"
    );

    await click(tbdHeaderCheckbox());
    assert.true(tbdCheckboxes().every((box) => !box.checked));
  });

  test("a topic already duplicated to the same occurrence shows a link and starts unchecked, but its checkbox is not disabled", async function (assert) {
    this.topics = [
      topic({
        already_duplicated: true,
        existing_duplicate_topic_id: 55,
        existing_duplicate_topic_url: "/t/55",
        selected: false,
      }),
    ];

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
        />
      </template>
    );

    assert.dom("tbody input[type=checkbox]").isNotChecked();
    assert.dom("tbody input[type=checkbox]").isNotDisabled();
    assert
      .dom(".event-duplicator-already-duplicated a")
      .hasAttribute("href", "/t/55");
  });

  test("a row just duplicated in this session (per @result) is disabled, links to the new topic, and is excluded from a later confirm even though still selected", async function (assert) {
    this.topics = [topic({ id: 1, selected: true })];
    this.result = {
      duplicated: [{ topic_id: 1, new_topic_id: 77, new_topic_url: "/t/77" }],
      skipped: [],
    };
    this.onConfirm = sinon.spy();

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
          @result={{this.result}}
          @onConfirm={{this.onConfirm}}
        />
      </template>
    );

    assert.dom("tbody input[type=checkbox]").isDisabled();
    assert
      .dom(".event-duplicator-already-duplicated a")
      .hasAttribute("href", "/t/77");

    await click(".btn-primary");
    const [selectedItems] = this.onConfirm.firstCall.args;
    assert.strictEqual(
      selectedItems.length,
      0,
      "already-duplicated-this-session row is not resubmitted"
    );
  });

  test("confirm submits only selected, not-yet-duplicated rows with topic/startsAt/tbd/title", async function (assert) {
    this.topics = [
      topic({ id: 1, title: "Grand Prix", selected: true }),
      topic({ id: 2, title: "Signature Race", selected: false }),
    ];
    this.onConfirm = sinon.spy();

    await render(
      <template>
        <EventDuplicatorReview
          @topics={{this.topics}}
          @isDuplicating={{false}}
          @onConfirm={{this.onConfirm}}
        />
      </template>
    );

    await click(".btn-primary");

    const [selectedItems] = this.onConfirm.firstCall.args;
    assert.strictEqual(selectedItems.length, 1);
    assert.strictEqual(selectedItems[0].topic.id, 1);
    assert.strictEqual(selectedItems[0].title, "Grand Prix");
    assert.strictEqual(selectedItems[0].tbd, true);
    assert.strictEqual(selectedItems[0].startsAt, topic().proposed_start);
  });
});
