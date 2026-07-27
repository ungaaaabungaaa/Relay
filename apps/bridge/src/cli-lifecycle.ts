type BridgeShutdownResources = {
  cloudRuntime: { close(): Promise<void> };
  server: { close(): void };
  adminServer: { close(): void };
  adapter: { stop(): void };
};

export function createBridgeShutdown(resources: BridgeShutdownResources) {
  let shutdown: Promise<void> | undefined;
  return (): Promise<void> => {
    shutdown ??= (async () => {
      try {
        await resources.cloudRuntime.close();
      } finally {
        resources.server.close();
        resources.adminServer.close();
        resources.adapter.stop();
      }
    })();
    return shutdown;
  };
}
