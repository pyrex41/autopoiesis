/**
 * Discharge-report store — the substance layer of the AETHER / Shen-Backpressure
 * cockpit. A discharge_report.json is the audit-grade artifact `sb` writes after
 * every gate run: per-rule, per-premise evidence of how each invariant was
 * discharged (statically by guard types, by runtime sampling, or unproven),
 * with concrete counter-examples and reproduction commands for failures.
 *
 * Types mirror schema_version: 1.
 */
import { createSignal } from "solid-js";

export interface SpecFile {
  path: string;
  sha256: string;
}

export interface DischargeImpl {
  git_commit: string;
  git_dirty: boolean;
  target_languages: string[];
}

export interface DischargeTools {
  sb_version: string;
  shen_derive_version?: string;
  shengen_version?: string;
  shen_runtime?: string;
  shen_runtime_available?: boolean;
}

export interface DischargeSummary {
  rule_count: number;
  rules_discharged: number;
  rules_violated: number;
  rules_unproven: number;
  premises_total: number;
  premises_static: number;
  premises_runtime_sampled: number;
  premises_unproven: number;
}

/** static | runtime-sample | unproven */
export type DischargeKind = "static" | "runtime-sample" | "unproven" | string;

export interface Premise {
  id: string;
  expression: string;
  discharge: DischargeKind;
  discharge_basis: string;
  rationale: string;
  code_references?: string[];
  samples_passed: number;
  samples_failed: number;
  sample_seed: string | null;
}

export interface CounterExample {
  // Shape per the SB design memo: a case id, the spec output, the impl output,
  // and a ready-to-paste reproduction command. Fields are defensive — older
  // reports may name them differently.
  case_id?: string;
  id?: string;
  spec_output?: string;
  impl_output?: string;
  repro?: string;
  reproduction?: string;
  [k: string]: unknown;
}

export type RuleStatus = "discharged" | "violated" | "unproven" | string;

export interface Rule {
  name: string;
  kind: string; // wrapper | composite | guarded | constrained | define | ...
  spec_file: string;
  spec_excerpt: string;
  human_description: string;
  human_description_source?: string;
  premises: Premise[];
  status: RuleStatus;
  discharged_since_commit?: string;
  counter_examples: CounterExample[];
}

export interface DischargeReport {
  schema_version: number;
  generated_at: string;
  signature: unknown | null;
  spec: { files: SpecFile[]; rule_count: number };
  impl: DischargeImpl;
  tools: DischargeTools;
  summary: DischargeSummary;
  rules: Rule[];
}

/**
 * One iteration in the lineage: a discharge report in a `.sb/history/`
 * directory. The backend (`/api/aether/discharge-history`) returns these
 * newest-first with a lightweight summary, so the sidebar can render the
 * lineage without fetching every full report.
 */
export type HistoryStatus =
  | "discharged"
  | "violated"
  | "unproven"
  | "unreadable"
  | string;

export interface HistoryEntry {
  path: string; // absolute path, hand straight to load()
  timestamp: string; // ISO prefix from filename, e.g. 2026-05-28T181632Z
  git_sha: string; // git short SHA from filename
  generated_at?: string;
  status: HistoryStatus;
  summary: DischargeSummary | null;
}

const [report, setReport] = createSignal<DischargeReport | null>(null);
const [reportPath, setReportPath] = createSignal<string>("");
const [loading, setLoading] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);

const [history, setHistory] = createSignal<HistoryEntry[]>([]);
const [historyLoading, setHistoryLoading] = createSignal(false);
const [historyError, setHistoryError] = createSignal<string | null>(null);
// The path of the report currently loaded — lets the sidebar highlight it.
const [selectedPath, setSelectedPath] = createSignal<string>("");

async function load(path: string): Promise<void> {
  setReportPath(path);
  setSelectedPath(path);
  setLoading(true);
  setError(null);
  try {
    const res = await fetch(`/api/aether/discharge?report=${encodeURIComponent(path)}`);
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`${res.status}: ${text.slice(0, 200)}`);
    }
    const data = (await res.json()) as DischargeReport;
    setReport(data);
  } catch (err) {
    setError(err instanceof Error ? err.message : String(err));
    setReport(null);
  } finally {
    setLoading(false);
  }
}

/** Load the lineage of discharge reports in a `.sb/history/` directory. */
async function loadHistory(dir: string): Promise<void> {
  setHistoryLoading(true);
  setHistoryError(null);
  try {
    const res = await fetch(
      `/api/aether/discharge-history?dir=${encodeURIComponent(dir)}`,
    );
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`${res.status}: ${text.slice(0, 200)}`);
    }
    const data = (await res.json()) as { entries: HistoryEntry[]; count: number };
    setHistory(data.entries ?? []);
  } catch (err) {
    setHistoryError(err instanceof Error ? err.message : String(err));
    setHistory([]);
  } finally {
    setHistoryLoading(false);
  }
}

/** Rules sorted so problems surface first: violated, then unproven, then discharged. */
function sortedRules(): Rule[] {
  const r = report();
  if (!r) return [];
  const rank = (s: RuleStatus) =>
    s === "violated" ? 0 : s === "unproven" ? 1 : 2;
  return [...r.rules].sort((a, b) => rank(a.status) - rank(b.status));
}

export const dischargeStore = {
  report,
  reportPath,
  loading,
  error,
  load,
  sortedRules,
  history,
  historyLoading,
  historyError,
  selectedPath,
  loadHistory,
};
