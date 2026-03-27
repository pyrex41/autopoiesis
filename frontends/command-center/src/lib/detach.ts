const CHANNEL_NAME = "ap-detach";

let channel: BroadcastChannel | null = null;

function getChannel(): BroadcastChannel {
  if (!channel) channel = new BroadcastChannel(CHANNEL_NAME);
  return channel;
}

export function detachPanel(panelId: string) {
  const w = 800, h = 600;
  const left = window.screenX + (window.outerWidth - w) / 2;
  const top = window.screenY + (window.outerHeight - h) / 2;
  window.open(
    `detached.html?panel=${panelId}`,
    `ap-${panelId}`,
    `width=${w},height=${h},left=${left},top=${top}`
  );
}

export function isDetached(): boolean {
  return new URLSearchParams(window.location.search).has("panel");
}

export function getDetachedPanel(): string | null {
  return new URLSearchParams(window.location.search).get("panel");
}

export function broadcastMessage(type: string, data: unknown) {
  getChannel().postMessage({ type, data });
}

export function onDetachMessage(handler: (msg: { type: string; data: unknown }) => void) {
  const ch = getChannel();
  const listener = (e: MessageEvent) => handler(e.data);
  ch.addEventListener("message", listener);
  return () => ch.removeEventListener("message", listener);
}
