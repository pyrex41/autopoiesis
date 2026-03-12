import { type Component, Show } from "solid-js";
import { navigationStore } from "../stores/navigation";
import "../styles/breadcrumb.css";

const Breadcrumb: Component = () => {
  return (
    <div class="breadcrumb">
      <Show when={navigationStore.canGoBack()}>
        <button class="breadcrumb-back" onClick={() => navigationStore.goBack()} title="Go back">
          ←
        </button>
        <span class="breadcrumb-separator">›</span>
      </Show>
      <span class="breadcrumb-current">{navigationStore.current()?.label}</span>
    </div>
  );
};

export default Breadcrumb;
