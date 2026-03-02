import { onMount, onCleanup, type Component } from "solid-js";
import { dagStore } from "../stores/dag";
import { fitToView } from "../graph/globals";

/**
 * Global keyboard shortcut handler.
 * Vim-style navigation (hjkl), plus power-user shortcuts.
 */
const KeyboardHandler: Component = () => {
  function handleKey(e: KeyboardEvent) {
    // Skip if typing in an input
    const tag = (e.target as HTMLElement)?.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;

    // Ctrl/Cmd + K: command palette
    if ((e.ctrlKey || e.metaKey) && e.key === "k") {
      e.preventDefault();
      dagStore.setShowCommandPalette(true);
      return;
    }

    switch (e.key) {
      // Navigation (vim)
      case "h":
        dagStore.navigateToParent();
        break;
      case "l":
        dagStore.navigateToChild();
        break;
      case "j":
        dagStore.navigateToSibling(1);
        break;
      case "k":
        dagStore.navigateToSibling(-1);
        break;

      // Fit to view
      case "f":
        fitToView();
        break;

      // Toggle inspector
      case "i":
        dagStore.setDetailPanelOpen(!dagStore.detailPanelOpen());
        break;

      // Toggle diff mode
      case "d":
        dagStore.setDiffMode(!dagStore.diffMode());
        break;

      // Focus search
      case "/":
        e.preventDefault();
        document.querySelector<HTMLInputElement>(".search-input")?.focus();
        break;

      // Collapse/expand selected node
      case "Space":
      case " ": {
        const sel = dagStore.selection();
        if (sel.primary) {
          e.preventDefault();
          dagStore.toggleCollapse(sel.primary);
        }
        break;
      }

      // Clear selection
      case "Escape":
        if (dagStore.showCommandPalette()) {
          dagStore.setShowCommandPalette(false);
        } else if (dagStore.searchQuery()) {
          dagStore.setSearchQuery("");
        } else {
          dagStore.clearSelection();
          dagStore.setDiffResult(null);
        }
        break;

      // Enter: compute diff if two selected
      case "Enter": {
        const sel = dagStore.selection();
        if (sel.primary && sel.secondary) {
          dagStore.computeDiff();
        }
        break;
      }

      // Question mark: show shortcuts
      case "?":
        dagStore.setShowCommandPalette(true);
        break;
    }
  }

  onMount(() => window.addEventListener("keydown", handleKey));
  onCleanup(() => window.removeEventListener("keydown", handleKey));

  return null;
};

export default KeyboardHandler;
