import { type Operation, type State } from "./engine";
export interface Transaction {
    id: string;
    epoch: string;
    base_revision: number;
    ops: Operation[];
    /** Only on this revision (the base again), else refused as stale. */
    if_revision?: number;
}
export interface AcceptedTransaction extends Transaction {
    revision: number;
    author: string;
}
export interface Snapshot {
    id: string;
    engine: string;
    epoch: string;
    revision: number;
    state: State;
    accepted?: string[];
}
export interface Receipt {
    id: string;
    revision: number;
    duplicate?: boolean;
}
/** How a document reaches its authority: a room's channel, or a test's fake. */
export interface DocumentLink {
    send(documentId: string, transaction: Transaction): Promise<Receipt>;
}
/** Thrown by a link when the server refused a transaction (not when the connection failed). */
export declare class Refused extends Error {
    readonly reason: string;
    constructor(reason: string);
}
export type DocumentEvent = {
    type: "change";
    state: State;
    origin: "local" | "remote" | "reset";
} | {
    type: "refused";
    transaction: Transaction;
    reason: string;
} | {
    type: "out_of_step";
    reason: string;
} | {
    type: "settled";
};
export interface DocumentOptions {
    /** The actor's key, given to the engine for local changes. */
    author: string;
    /** A new id for each transaction. */
    newId?: () => string;
    /** Called after every change of the pending queue, to keep it (an offline store). */
    persist?: (snapshot: Snapshot, pending: Transaction[]) => void;
    /**
     * Pending transactions kept from before (a draft), of the snapshot's
     * epoch: those the snapshot's `accepted` does not name are replayed and
     * sent.
     */
    pending?: Transaction[];
    /**
     * Changes made within `delay` milliseconds of the first go as one
     * transaction, of at most `maxOps` operations (900).
     */
    batch?: {
        delay: number;
        maxOps?: number;
    };
}
export declare class SharedDocument {
    private readonly link;
    private readonly options;
    readonly id: string;
    private readonly engine;
    private accepted;
    private queue;
    private view;
    private sending;
    private acked;
    private online;
    private held;
    private sent;
    private batching;
    private listeners;
    private settledWaiters;
    constructor(snapshot: Snapshot, link: DocumentLink, options: DocumentOptions);
    /** The state people see: the accepted state with this browser's pending changes. */
    get state(): State;
    /** The revision of the accepted state. */
    get revision(): number;
    get epoch(): string;
    /** This browser's transactions the server has not accepted yet. */
    get pending(): readonly Transaction[];
    on(listener: (event: DocumentEvent) => void): () => void;
    /**
     * Makes a change: applies it to the view now, and sends it. Gives the
     * transaction, or the engine's reason when the operations do not apply.
     */
    change(ops: Operation[]): {
        ok: true;
        transaction: Transaction;
    } | {
        ok: false;
        reason: string;
    };
    /** Keeps transactions from going until `release()`; changes still show, and batch. */
    hold(): void;
    /** Lets held transactions go. */
    release(): void;
    /** Sends the batching transaction now, without waiting for its delay. */
    flush(): void;
    /** A transaction the server accepted, pushed to every browser with the document open. */
    receive(event: AcceptedTransaction): void;
    /**
     * The document as the server has it now, after a reconnect or when this
     * copy was out of step. `accepted` names pending transactions the server
     * already has; the others are sent again, unchanged.
     */
    reset(snapshot: Snapshot): void;
    /** Whether the link can send; offline, transactions wait in the queue. */
    setOnline(online: boolean): void;
    private joinLast;
    private newTransaction;
    private endBatch;
    /** Resolves when every pending transaction has been accepted. */
    settled(): Promise<void>;
    private replay;
    private pump;
    private acknowledged;
    private failed;
    private outOfStep;
    private persist;
    private emit;
}
