import { createSignal } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";

interface EvolutionState {
  running: boolean;
  generation: number;
  totalGenerations: number;
  populationSize: number;
  fitnessHistory: Array<{ generation: number; best: number; avg: number; worst: number }>;
}

const [evolution, setEvolution] = createSignal<EvolutionState>({
  running: false,
  generation: 0,
  totalGenerations: 0,
  populationSize: 0,
  fitnessHistory: [],
});

function startEvolution(opts?: { generations?: number; mutationRate?: number; populationSize?: number }) {
  wsStore.send({
    type: "start_evolution",
    generations: opts?.generations ?? 10,
    mutationRate: opts?.mutationRate ?? 0.1,
    populationSize: opts?.populationSize ?? 10,
  } as any);
}

function stopEvolution() {
  wsStore.send({ type: "stop_evolution" } as any);
}

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "evolution_started": {
      setEvolution((prev) => ({
        ...prev,
        running: true,
        generation: 0,
        totalGenerations: (msg as any).generations ?? 10,
        populationSize: (msg as any).populationSize ?? 10,
        fitnessHistory: [],
      }));
      break;
    }
    case "evolution_progress": {
      const gen = (msg as any).generation as number;
      const best = (msg as any).bestFitness as number ?? 0;
      const avg = (msg as any).avgFitness as number ?? 0;
      const worst = (msg as any).worstFitness as number ?? 0;
      setEvolution((prev) => ({
        ...prev,
        generation: gen,
        fitnessHistory: [...prev.fitnessHistory, { generation: gen, best, avg, worst }],
      }));
      break;
    }
    case "evolution_complete": {
      setEvolution((prev) => ({ ...prev, running: false }));
      break;
    }
    case "evolution_stopped": {
      setEvolution((prev) => ({ ...prev, running: false }));
      break;
    }
    case "evolution_error": {
      setEvolution((prev) => ({ ...prev, running: false }));
      break;
    }
    case "evolution_status": {
      setEvolution((prev) => ({
        ...prev,
        running: (msg as any).running === true,
        generation: (msg as any).generation ?? prev.generation,
      }));
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.subscribe("evolution");
  wsStore.send({ type: "evolution_status" } as any);
}

export const evolutionStore = {
  evolution,
  startEvolution,
  stopEvolution,
  init,
};
