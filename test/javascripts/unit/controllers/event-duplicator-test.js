import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import { Promise } from "rsvp";
import sinon from "sinon";

module("Unit | Controller | event-duplicator", function (hooks) {
  setupTest(hooks);

  function controller(owner) {
    return owner.lookup("controller:event-duplicator");
  }

  function stubEventDuplicator(owner, duplicateStub) {
    owner.unregister("service:event-duplicator");
    owner.register(
      "service:event-duplicator",
      { duplicate: duplicateStub },
      { instantiate: false }
    );
  }

  function selectedItem(overrides = {}) {
    return {
      topic: { id: 1, already_duplicated: false },
      startsAt: "2027-07-04T12:00:00.000Z",
      tbd: true,
      title: "Grand Prix 2027",
      ...overrides,
    };
  }

  test("setDateStrategy transitions with only date_strategy as a query param", function (assert) {
    const ctrl = controller(this.owner);
    const transitionTo = sinon.stub(ctrl.router, "transitionTo");

    ctrl.setDateStrategy({ target: { value: "nth_weekday_of_month" } });

    assert.true(transitionTo.calledOnce);
    const [routeName, options] = transitionTo.firstCall.args;
    assert.strictEqual(routeName, "event-duplicator");
    assert.deepEqual(options.queryParams, {
      date_strategy: "nth_weekday_of_month",
    });
  });

  test("confirmDuplication maps each selected item to topic_id/starts_at/tbd/title, and sends force only for already-duplicated rows", async function (assert) {
    const duplicate = sinon.stub().resolves({ duplicated: [], skipped: [] });
    stubEventDuplicator(this.owner, duplicate);
    const ctrl = controller(this.owner);

    await ctrl.confirmDuplication([
      selectedItem({ topic: { id: 1, already_duplicated: false } }),
      selectedItem({
        topic: { id: 2, already_duplicated: true },
        title: "Grand Prix 2027 (re-run)",
      }),
    ]);

    assert.true(duplicate.calledOnce);
    const [items] = duplicate.firstCall.args;
    assert.deepEqual(items, [
      {
        topic_id: 1,
        starts_at: "2027-07-04T12:00:00.000Z",
        tbd: true,
        title: "Grand Prix 2027",
        force: false,
      },
      {
        topic_id: 2,
        starts_at: "2027-07-04T12:00:00.000Z",
        tbd: true,
        title: "Grand Prix 2027 (re-run)",
        force: true,
      },
    ]);
  });

  test("confirmDuplication toggles isDuplicating around the request", async function (assert) {
    let resolveDuplicate;
    const duplicate = sinon.stub().returns(
      new Promise((resolve) => {
        resolveDuplicate = resolve;
      })
    );
    stubEventDuplicator(this.owner, duplicate);
    const ctrl = controller(this.owner);

    const promise = ctrl.confirmDuplication([selectedItem()]);
    assert.true(ctrl.isDuplicating);

    resolveDuplicate({ duplicated: [], skipped: [] });
    await promise;

    assert.false(ctrl.isDuplicating);
  });

  test("confirmDuplication attaches the submitted title to each duplicated/skipped entry, since the backend response only carries topic ids", async function (assert) {
    const duplicate = sinon.stub().resolves({
      duplicated: [{ topic_id: 1, new_topic_id: 99, new_topic_url: "/t/99" }],
      skipped: [{ topic_id: 2, reason: "already_duplicated" }],
    });
    stubEventDuplicator(this.owner, duplicate);
    const ctrl = controller(this.owner);

    await ctrl.confirmDuplication([
      selectedItem({ topic: { id: 1 }, title: "Grand Prix 2027" }),
      selectedItem({ topic: { id: 2 }, title: "Signature Race 2027" }),
    ]);

    assert.strictEqual(ctrl.result.duplicated[0].title, "Grand Prix 2027");
    assert.strictEqual(ctrl.result.skipped[0].title, "Signature Race 2027");
  });

  test("confirmDuplication accumulates `duplicated` across submissions rather than replacing it, so a retry doesn't lose earlier successes", async function (assert) {
    // A single stub with per-call responses -- `@service eventDuplicator` is
    // resolved and cached on first access, so swapping the registered
    // service mid-test (as an earlier version of this test tried) silently
    // keeps talking to the first stub instead of a freshly-registered one.
    const duplicate = sinon.stub();
    duplicate.onCall(0).resolves({
      duplicated: [{ topic_id: 1, new_topic_id: 99, new_topic_url: "/t/99" }],
      skipped: [{ topic_id: 2, reason: "some failure" }],
    });
    duplicate.onCall(1).resolves({
      duplicated: [{ topic_id: 2, new_topic_id: 100, new_topic_url: "/t/100" }],
      skipped: [],
    });
    stubEventDuplicator(this.owner, duplicate);
    const ctrl = controller(this.owner);

    await ctrl.confirmDuplication([
      selectedItem({ topic: { id: 1 }, title: "First" }),
      selectedItem({ topic: { id: 2 }, title: "Second" }),
    ]);
    assert.strictEqual(ctrl.result.duplicated.length, 1);

    // Retry with only the previously-failed item.
    await ctrl.confirmDuplication([
      selectedItem({ topic: { id: 2 }, title: "Second" }),
    ]);

    assert.strictEqual(
      ctrl.result.duplicated.length,
      2,
      "earlier success from the first submission is preserved"
    );
    assert.deepEqual(
      ctrl.result.duplicated.map((entry) => entry.topic_id).sort(),
      [1, 2]
    );
    assert.strictEqual(
      ctrl.result.skipped.length,
      0,
      "skipped list reflects only the latest attempt, not accumulated"
    );
  });
});
