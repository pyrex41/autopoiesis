/**
 * Projects store — the cockpit home. Lists Shen-Backpressure projects
 * (repos with a .sb/history/ dir) discovered by the backend, so the user
 * can pick one and drop into its iteration lineage.
 */
import { createSignal } from "solid-js";

export type ProjectStatus =
  | "discharged"
  | "violated"
  | "unproven"
  | "unreadable"
  | string;

export interface ProjectEntry {
  name: string;
  /** absolute path to the project's .sb/history/ dir — hand to loadHistory() */
  path: string;
  /** absolute path to the project root (dir with sb.toml) — hand to startRun() */
  root: string;
  /** path relative to the scanned root, for disambiguation */
  rel?: string;
  iteration_count: number;
  latest_status: ProjectStatus | null;
  latest_timestamp: string | null;
}

const [projects, setProjects] = createSignal<ProjectEntry[]>([]);
const [root, setRoot] = createSignal<string>("");
const [loading, setLoading] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);

/** Discover projects under DIR (optional; backend falls back to its default root). */
async function loadProjects(dir?: string): Promise<void> {
  setLoading(true);
  setError(null);
  try {
    const qs = dir ? `?root=${encodeURIComponent(dir)}` : "";
    const res = await fetch(`/api/aether/projects${qs}`);
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`${res.status}: ${text.slice(0, 200)}`);
    }
    const data = (await res.json()) as {
      root: string;
      projects: ProjectEntry[];
      count: number;
    };
    setProjects(data.projects ?? []);
    setRoot(data.root ?? "");
  } catch (err) {
    setError(err instanceof Error ? err.message : String(err));
    setProjects([]);
  } finally {
    setLoading(false);
  }
}

export const projectsStore = {
  projects,
  root,
  loading,
  error,
  loadProjects,
};
