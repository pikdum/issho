import type { Snapshot, Transaction } from "./document";
export interface Draft {
    epoch: string;
    revision: number;
    pending: Transaction[];
}
/** Where drafts are kept: IndexedDB in a browser, memory in a test. */
export interface DraftStore {
    load(key: string): Promise<Draft | null>;
    save(key: string, draft: Draft): Promise<void>;
    remove(key: string): Promise<void>;
}
export declare class MemoryDraftStore implements DraftStore {
    readonly drafts: Map<string, Draft>;
    load(key: string): Promise<Draft | null>;
    save(key: string, draft: Draft): Promise<void>;
    remove(key: string): Promise<void>;
}
export declare class IndexedDraftStore implements DraftStore {
    private database;
    private open;
    private run;
    load(key: string): Promise<Draft | null>;
    save(key: string, draft: Draft): Promise<void>;
    remove(key: string): Promise<void>;
}
/** IndexedDB when the browser has it and allows it, else memory (drafts last only while the tab is open). */
export declare function defaultDraftStore(): {
    store: DraftStore;
    durable: boolean;
};
export interface SessionEnvironment {
    storage?: Pick<Storage, "getItem" | "setItem"> | null;
    locks?: Pick<LockManager, "request"> | null;
    newId?: () => string;
}
/**
 * The tab's session for a scope: the same after a reload of the tab, and a
 * new one for a tab that copied it (a duplicated tab copies sessionStorage):
 * a Web Lock held for the tab's life tells them apart.
 */
export declare function claimSession(scope: string, env?: SessionEnvironment): Promise<string>;
/** The key of a document's draft: origin, room, document, actor and tab session. */
export declare function draftKey(parts: {
    room: string;
    document: string;
    actor: string;
    session: string;
}): string;
export declare function draftOf(snapshot: Snapshot, pending: Transaction[]): Draft;
