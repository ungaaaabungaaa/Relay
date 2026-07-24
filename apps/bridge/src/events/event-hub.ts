export type RelayEvent = {
  id: number;
  type: string;
  data: unknown;
  createdAt: number;
};

export class EventHub {
  private sequence = 0;
  private readonly events: RelayEvent[] = [];
  private readonly capacity: number;

  constructor(capacity = 500) {
    this.capacity = capacity;
  }

  publish(type: string, data: unknown): RelayEvent {
    const event = { id: ++this.sequence, type, data, createdAt: Date.now() };
    this.events.push(event);
    while (this.events.length > this.capacity) this.events.shift();
    return event;
  }

  after(id: number): RelayEvent[] {
    return this.events.filter((event) => event.id > id);
  }
}
