import { type Component, For, Switch, Match } from "solid-js";
import DiffView from "./DiffView";
import FileTree from "./FileTree";
import CodeBlock from "./CodeBlock";
import TimelineSlice from "./TimelineSlice";
import SnapshotCard from "./SnapshotCard";
import SandboxCard from "./SandboxCard";
import DataTable from "./DataTable";

/** A generative UI block returned by Jarvis alongside text responses */
export interface Block {
  type: string;
  data: any;
  /** Optional title displayed above the block */
  title?: string;
}

interface BlockRendererProps {
  blocks: Block[];
}

/** Renders a list of typed blocks as rich UI components */
const BlockRenderer: Component<BlockRendererProps> = (props) => {
  return (
    <div class="block-renderer">
      <For each={props.blocks}>
        {(block) => (
          <div class="block-container" data-block-type={block.type}>
            {block.title && <div class="block-title">{block.title}</div>}
            <Switch fallback={<UnknownBlock type={block.type} data={block.data} />}>
              <Match when={block.type === "diff-view"}>
                <DiffView data={block.data} />
              </Match>
              <Match when={block.type === "file-tree"}>
                <FileTree data={block.data} />
              </Match>
              <Match when={block.type === "code-block"}>
                <CodeBlock data={block.data} />
              </Match>
              <Match when={block.type === "timeline-slice"}>
                <TimelineSlice data={block.data} />
              </Match>
              <Match when={block.type === "snapshot-detail"}>
                <SnapshotCard data={block.data} />
              </Match>
              <Match when={block.type === "sandbox-status"}>
                <SandboxCard data={block.data} />
              </Match>
              <Match when={block.type === "table"}>
                <DataTable data={block.data} />
              </Match>
            </Switch>
          </div>
        )}
      </For>
    </div>
  );
};

/** Fallback for unknown block types — renders raw JSON */
const UnknownBlock: Component<{ type: string; data: any }> = (props) => (
  <div class="block-unknown">
    <div class="block-unknown-type">{props.type}</div>
    <pre class="block-unknown-data">{JSON.stringify(props.data, null, 2)}</pre>
  </div>
);

export default BlockRenderer;
