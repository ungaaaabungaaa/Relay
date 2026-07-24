export type RelayEvent = {
  id: number;
  type: string;
  data: unknown;
  createdAt: number;
};

export class EventHub {
  private sequence = 0;
  private readonly events: RelayEvent[] = [];
  private readonly listeners = new Set<(event: RelayEvent) => void>();
  private readonly capacity: number;

  constructor(capacity = 500) {
    this.capacity = capacity;
  }

  publish(type: string, data: unknown): RelayEvent {
    const event = { id: ++this.sequence, type, data, createdAt: Date.now() };
    this.events.push(event);
    while (this.events.length > this.capacity) this.events.shift();
    for (const listener of this.listeners) listener(event);
    return event;
  }

  after(id: number): RelayEvent[] {
    return this.events.filter((event) => event.id > id);
  }

  get latestEventId(): number {
    return this.sequence;
  }

  resumeAfter(id: number): {
    events: RelayEvent[];
    snapshotRequired: boolean;
  } {
    const earliest = this.events[0]?.id;
    const snapshotRequired = earliest !== undefined && id < earliest - 1;
    return {
      events: snapshotRequired ? [] : this.after(id),
      snapshotRequired,
    };
  }

  subscribe(listener: (event: RelayEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }
}
