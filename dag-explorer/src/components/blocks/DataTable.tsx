import { type Component, For, Show, createSignal } from "solid-js";

interface DataTableData {
  columns: string[];
  rows: any[][];
  title?: string;
}

const DataTable: Component<{ data: DataTableData }> = (props) => {
  const [sortCol, setSortCol] = createSignal(-1);
  const [sortAsc, setSortAsc] = createSignal(true);

  const sortedRows = () => {
    const col = sortCol();
    if (col < 0) return props.data.rows;
    const asc = sortAsc();
    return [...props.data.rows].sort((a, b) => {
      const va = a[col], vb = b[col];
      const cmp = typeof va === "number" && typeof vb === "number"
        ? va - vb
        : String(va).localeCompare(String(vb));
      return asc ? cmp : -cmp;
    });
  };

  const handleSort = (col: number) => {
    if (sortCol() === col) setSortAsc(!sortAsc());
    else { setSortCol(col); setSortAsc(true); }
  };

  return (
    <div class="block-table-wrap">
      <table class="block-table">
        <thead>
          <tr>
            <For each={props.data.columns}>
              {(col, idx) => (
                <th onClick={() => handleSort(idx())} class="block-table-th">
                  {col}
                  <Show when={sortCol() === idx()}>
                    <span>{sortAsc() ? " \u25B4" : " \u25BE"}</span>
                  </Show>
                </th>
              )}
            </For>
          </tr>
        </thead>
        <tbody>
          <For each={sortedRows()}>
            {(row) => (
              <tr>
                <For each={row}>
                  {(cell) => <td class="block-table-td">{String(cell)}</td>}
                </For>
              </tr>
            )}
          </For>
        </tbody>
      </table>
    </div>
  );
};

export default DataTable;
