import { type Component, onMount, createSignal } from "solid-js";
import AppShell from "./components/AppShell";

const App: Component = () => {
  const [ready, setReady] = createSignal(false);

  onMount(() => {
    requestAnimationFrame(() => setReady(true));
  });

  return (
    <div class="app-layout" classList={{ "app-ready": ready() }}>
      <AppShell />
    </div>
  );
};

export default App;
