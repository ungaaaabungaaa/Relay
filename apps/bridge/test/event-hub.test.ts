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
