import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import sinon from "sinon";

module("Unit | Controller | event-duplicator-new", function (hooks) {
  setupTest(hooks);

  function controller(owner) {
    return owner.lookup("controller:event-duplicator-new");
  }

  test("canProceed requires both a category and at least one tag", function (assert) {
    const ctrl = controller(this.owner);

    assert.false(ctrl.canProceed, "neither set");

    ctrl.setCategoryId(1);
    assert.false(ctrl.canProceed, "category only");

    ctrl.setTags(["grand-prix"]);
    assert.true(ctrl.canProceed, "both set");
  });

  test("setTags normalizes TagChooser's tag objects to plain name strings", function (assert) {
    const ctrl = controller(this.owner);

    ctrl.setTags([
      { id: 1, name: "grand-prix" },
      { id: 2, name: "signature-race" },
    ]);

    assert.deepEqual(ctrl.tags, ["grand-prix", "signature-race"]);
  });

  test("setTags accepts plain strings unchanged", function (assert) {
    const ctrl = controller(this.owner);

    ctrl.setTags(["grand-prix", "signature-race"]);

    assert.deepEqual(ctrl.tags, ["grand-prix", "signature-race"]);
  });

  test("setTags treats a missing value as no tags", function (assert) {
    const ctrl = controller(this.owner);

    ctrl.setTags(undefined);

    assert.deepEqual(ctrl.tags, []);
  });

  test("setStartsAfter/setStartsBefore read from the native input event, empty string becomes null", function (assert) {
    const ctrl = controller(this.owner);

    ctrl.setStartsAfter({ target: { value: "2026-01-01" } });
    assert.strictEqual(ctrl.startsAfter, "2026-01-01");
    ctrl.setStartsAfter({ target: { value: "" } });
    assert.strictEqual(ctrl.startsAfter, null);

    ctrl.setStartsBefore({ target: { value: "2026-12-31" } });
    assert.strictEqual(ctrl.startsBefore, "2026-12-31");
    ctrl.setStartsBefore({ target: { value: "" } });
    assert.strictEqual(ctrl.startsBefore, null);
  });

  test("clearStartsAfter/clearStartsBefore reset to null directly", function (assert) {
    const ctrl = controller(this.owner);

    ctrl.setStartsAfter({ target: { value: "2026-01-01" } });
    ctrl.setStartsBefore({ target: { value: "2026-12-31" } });

    ctrl.clearStartsAfter();
    ctrl.clearStartsBefore();

    assert.strictEqual(ctrl.startsAfter, null);
    assert.strictEqual(ctrl.startsBefore, null);
  });

  test("proceed transitions to the review route with category/tags/dates, and explicitly nulls topic_id", function (assert) {
    const ctrl = controller(this.owner);
    const transitionTo = sinon.stub(ctrl.router, "transitionTo");

    ctrl.setCategoryId(7);
    ctrl.setTags(["grand-prix", "signature-race"]);
    ctrl.setStartsAfter({ target: { value: "2026-01-01" } });
    ctrl.setStartsBefore({ target: { value: "2026-12-31" } });

    ctrl.proceed();

    assert.true(transitionTo.calledOnce);
    const [routeName, options] = transitionTo.firstCall.args;
    assert.strictEqual(routeName, "event-duplicator");
    assert.deepEqual(options.queryParams, {
      topic_id: null,
      category_id: 7,
      tags: "grand-prix,signature-race",
      starts_after: "2026-01-01",
      starts_before: "2026-12-31",
    });
  });

  test("proceed sends null (not empty strings) for unset date filters", function (assert) {
    const ctrl = controller(this.owner);
    const transitionTo = sinon.stub(ctrl.router, "transitionTo");

    ctrl.setCategoryId(7);
    ctrl.setTags(["grand-prix"]);

    ctrl.proceed();

    const [, options] = transitionTo.firstCall.args;
    assert.strictEqual(options.queryParams.starts_after, null);
    assert.strictEqual(options.queryParams.starts_before, null);
  });
});
