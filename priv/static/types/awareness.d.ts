import type { Json } from "./engine";
export type AwarenessState = {
    [key: string]: Json;
};
/**
 * A component's own keys in a state: what it set under its document in
 * `blocks` (an empty object for none). Issho owns a state's top-level keys
 * (`place`, `locks`, `status`, `pointer`, `view`, `motion`, `path`,
 * `blocks`); a component keeps its own under its document.
 */
export declare function blockOf(state: AwarenessState | null | undefined, doc: string): AwarenessState;
/** A state's blocks with a component's keys merged into its own (`null` removes a key). */
export declare function withBlock(state: AwarenessState | null | undefined, doc: string, changes: AwarenessState): Json;
export interface Peer {
    session: string;
    key: string;
    state: AwarenessState;
}
export interface Frame {
    node: string;
    full: boolean;
    states: Record<string, {
        key: string;
        state: AwarenessState;
    }>;
    gone: string[];
}
export interface AwarenessOptions {
    /** Milliseconds between this browser's sends, at most one each (50). */
    interval?: number;
    /** Milliseconds after which a node that sent nothing is gone (15000). */
    staleAfter?: number;
    now?: () => number;
    setTimer?: (fn: () => void, ms: number) => unknown;
    clearTimer?: (timer: unknown) => void;
}
type Send = (state: AwarenessState | null) => Promise<unknown>;
export declare class Awareness {
    private readonly send;
    private local;
    private dirty;
    private timer;
    private lastSent;
    private nodes;
    private there;
    private told;
    private listeners;
    private readonly interval;
    private readonly staleAfter;
    private readonly now;
    private readonly setTimer;
    private readonly clearTimer;
    constructor(send: Send, options?: AwarenessOptions);
    /** This browser's state. */
    get state(): AwarenessState | null;
    /** Merges keys into this browser's state (`null` for a key removes it), and sends it soon. */
    set(changes: AwarenessState): void;
    /** Clears this browser's state for the others. */
    clear(): void;
    /** Sends the current state again, after a rejoin. */
    resend(): void;
    on(listener: (peers: Peer[]) => void): () => void;
    /** The others, from every node. */
    get peers(): Peer[];
    /** A frame the channel pushed. */
    receive(frame: Frame): void;
    /**
     * Whether a session was in the room when this browser joined it (or
     * joined it again): what it did before then is not news.
     */
    wasThere(session: string): boolean;
    /** Forgets every peer, after a disconnect. */
    reset(): void;
    dispose(): void;
    private schedule;
    private flush;
    private emit;
}
export {};
