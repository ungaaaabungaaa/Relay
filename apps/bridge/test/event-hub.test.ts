import assert from "node:assert/strict";
import { it } from "node:test";
import { EventHub } from "../src/events/event-hub.ts";

it("replays events after the last acknowledged sequence", () => {
  const hub = new EventHub(3);
  hub.publish("task.updated", { id: "1" });
  hub.publish("task.updated", { id: "2" });
  hub.publish("task.updated", { id: "3" });
  assert.deepEqual(hub.after(1).map((event) => event.id), [2, 3]);
});

it("requires a snapshot only when the requested sequence fell out of retention", () => {
  const hub = new EventHub(2);
  hub.publish("task.updated", { id: "1" });
  hub.publish("task.updated", { id: "2" });
  hub.publish("task.updated", { id: "3" });

  assert.equal(hub.resumeAfter(0).snapshotRequired, true);
  assert.equal(hub.resumeAfter(1).snapshotRequired, false);
  assert.deepEqual(
    hub.resumeAfter(1).events.map((event) => event.id),
    [2, 3],
  );
});

it("delivers new events to subscribers until they unsubscribe", () => {
  const hub = new EventHub();
  const delivered: number[] = [];
  const unsubscribe = hub.subscribe((event) => delivered.push(event.id));

  hub.publish("task.updated", { id: "1" });
  unsubscribe();
  hub.publish("task.updated", { id: "2" });

  assert.deepEqual(delivered, [1]);
});
