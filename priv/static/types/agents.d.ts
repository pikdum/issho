import type { Peer } from "./awareness";
import type { Person } from "./presence";
export type TaskState = "working" | "paused" | "stopped" | "failed";
export type StepState = "pending" | "active" | "done" | "skipped";
/** An agent's task, as its state in the room says it. */
export interface Task {
    title: string;
    steps: {
        label: string;
        state: StepState;
    }[];
    state: TaskState;
    note?: string;
    /** Who paused or stopped it. */
    by?: {
        key: string;
        name: string | null;
    } | null;
}
/** An agent at work, as the bar shows it. */
export interface AtWork {
    agent: Person;
    task: Task;
    /** Whether this person may pause, resume or stop it: the one it acts for. */
    mine: boolean;
}
/** The agents of the room with a task, in the order they came; one entry each. */
export declare function atWork(peers: Peer[], everyone: Person[], self: string): AtWork[];
export interface AgentsOptions {
    /** Pause, Resume or Stop clicked for an agent. */
    interrupt: (agent: string, action: "pause" | "resume" | "stop") => void;
    /** Whether to offer them for agents that work for someone else (the policy decides): false. */
    anyone?: boolean;
    /** The bar's accessible name ("Agents at work"). */
    label?: string;
}
/**
 * Draws the agents at work into an element; hidden with none. An agent's
 * entry is drawn again only when it changed, so a frame of the room's
 * awareness takes no one's focus from a button, nor closes their steps.
 */
export declare function drawAgents(element: HTMLElement, agents: AtWork[], options: AgentsOptions): void;
