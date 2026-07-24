import type {
  SecurityStore,
  StoredActionResult,
} from "../security/store.ts";

export type ActionContext = {
  deviceId: string;
  idempotencyKey: string;
  action: string;
  target: string | null;
};

export class ActionInProgressError extends Error {
  constructor() {
    super("action already in progress");
    this.name = "ActionInProgressError";
  }
}

export class ActionPreviouslyFailedError extends Error {
  constructor() {
    super("action previously failed");
    this.name = "ActionPreviouslyFailedError";
  }
}

export class IdempotencyConflictError extends Error {
  constructor() {
    super("idempotency key reused for another action");
    this.name = "IdempotencyConflictError";
  }
}

export class ActionExecutor {
  private readonly store: SecurityStore;

  constructor(store: SecurityStore) {
    this.store = store;
  }

  async run<T>(
    context: ActionContext,
    operation: () => Promise<T> | T,
  ): Promise<T> {
    const existing = this.store.getActionResult(
      context.deviceId,
      context.idempotencyKey,
    );
    if (existing) return readExisting<T>(context, existing);

    const claimed = this.store.claimAction(
      context.deviceId,
      context.idempotencyKey,
      context.action,
      context.target,
    );
    if (!claimed) {
      const raced = this.store.getActionResult(
        context.deviceId,
        context.idempotencyKey,
      );
      if (raced) return readExisting<T>(context, raced);
      throw new ActionInProgressError();
    }

    try {
      const result = await operation();
      this.store.finishAction(
        context.deviceId,
        context.idempotencyKey,
        "succeeded",
        JSON.stringify(result ?? null),
      );
      this.store.audit(
        context.deviceId,
        context.action,
        context.target,
        "succeeded",
      );
      return result;
    } catch (error) {
      this.store.finishAction(
        context.deviceId,
        context.idempotencyKey,
        "failed",
        null,
      );
      this.store.audit(
        context.deviceId,
        context.action,
        context.target,
        "failed",
      );
      throw error;
    }
  }
}

function readExisting<T>(
  context: ActionContext,
  stored: StoredActionResult,
): T {
  if (stored.action !== context.action || stored.target !== context.target) {
    throw new IdempotencyConflictError();
  }
  if (stored.status === "pending") throw new ActionInProgressError();
  if (stored.status === "failed") throw new ActionPreviouslyFailedError();
  return JSON.parse(stored.responseJson ?? "null") as T;
}
