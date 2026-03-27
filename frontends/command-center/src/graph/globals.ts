/**
 * Window-level functions exposed by DAGCanvas for cross-component access.
 * These avoid prop-drilling through the component tree.
 */

declare global {
  interface Window {
    __dagFitToView?: () => void;
    __dagCenterOnNode?: (nodeId: string) => void;
  }
}

export function fitToView() {
  window.__dagFitToView?.();
}

export function centerOnNode(nodeId: string) {
  window.__dagCenterOnNode?.(nodeId);
}
