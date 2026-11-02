import { Awareness, type AwarenessOptions, type AwarenessState } from "./awareness";
import { SharedDocument, type DocumentOptions } from "./document";
import { type Draft, type DraftStore, type SessionEnvironment } from "./drafts";
import { Presence } from "./presence";
/**
 * How a room reaches the server. The Phoenix channel is one transport
 * (`phoenixTransport`); a test's fake is another.
 */
export interface RoomTransport {
    /** Joins; resolves with the session id and what the token allows. */
    join(): Promise<{
        session: string;
        can: "read" | "write";
    }>;
    /** Sends a message; resolves with the reply, rejects with `Refused` when the server refused it. */
    push(event: string, payload: unknown): Promise<unknown>;
    /** Messages the server pushes: "tx", "aware", "presence_state", "presence_diff", "bye". */
    on(event: string, callback: (payload: never) => void): void;
    /** The connection's state: "joined" after each (re)join, "closed" when it drops. */
    onStatus(callback: (status: "joined" | "closed") => void): void;
    leave(): void;
}
export type RoomStatus = "connecting" | "live" | "offline" | "ended";
export interface RoomOptions {
    /** This actor's key, as the server knows it. */
    self: string;
    /** The room's name, for the drafts' keys. */
    room?: string;
    awareness?: AwarenessOptions;
    /** Where pending transactions are kept across reloads; none unless given. */
    drafts?: DraftStore;
    /** For tests: the tab session's storage and locks. */
    session?: SessionEnvironment;
}
/** A draft the server can no longer take: its transactions, for the app to offer back. */
export interface StaleDraft {
    document: string;
    draft: Draft;
    reason: "epoch_mismatch";
}
export declare class Room {
    private readonly transport;
    private readonly options;
    readonly presence: Presence;
    readonly awareness: Awareness;
    session: string | null;
    can: "read" | "write";
    private documents;
    private opening;
    private statusValue;
    private statusListeners;
    private joinedOnce;
    private tabSession;
    private writes;
    private draftListeners;
    constructor(transport: RoomTransport, options: RoomOptions);
    get status(): RoomStatus;
    onStatus(listener: (status: RoomStatus, reason?: string) => void): () => void;
    /** Joins the room. */
    connect(): Promise<void>;
    /**
     * Opens a document of the room (the room itself, or a path under it),
     * once for every component that asks. `batch` makes changes close
     * together one transaction (see `DocumentOptions`); the first open's
     * options hold.
     */
    open(documentId: string, options?: {
        batch?: DocumentOptions["batch"];
    }): Promise<SharedDocument>;
    /** Called with each draft the server could no longer take, when its document opens. */
    onStaleDraft(listener: (stale: StaleDraft) => void): () => void;
    /** Throws away a document's stale draft, once the app has offered it back. */
    discardStaleDraft(documentId: string): Promise<void>;
    private keep;
    /** Resolves when every draft write so far is done. */
    flushDrafts(): Promise<void>;
    private draftKey;
    /** Sets keys of this browser's awareness state: `place`, `locks`, `status`, your own. */
    aware(changes: AwarenessState): void;
    /**
     * Sets a component's own keys, under its document (`blocks`), so that the
     * page's components and Issho's own keys never write over each other's;
     * `null` removes a key. Read the others' with `blockOf(peer.state, doc)`.
     */
    awareBlock(doc: string, changes: AwarenessState): void;
    /**
     * Pauses, resumes or stops an agent at work in the room: allowed for the
     * person it acts for, and whomever the server's policy allows. Rejects
     * with `Refused` when it is not.
     */
    interrupt(agent: string, action: "pause" | "resume" | "stop"): Promise<void>;
    leave(): void;
    private rejoined;
    private reopen;
    private disconnected;
    private setStatus;
}
