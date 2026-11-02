/** A component with undo steps of its own. */
export interface HistoryOwner {
    /** Takes back the component's last step; false when it has none left. */
    undo(): boolean;
    /** Puts back the component's last undone step; false when it has none. */
    redo(): boolean;
    /** Forgets the steps it could redo: a new change was made somewhere on the page. */
    clearRedo?(): void;
}
export declare class PageHistory {
    private done;
    private undone;
    private listeners;
    /** A new step of the owner's: the page's redo steps are gone. */
    record(owner: HistoryOwner): void;
    /** Takes back the last step made on the page; false when there is none. */
    undo(): boolean;
    /** Puts back the last step undone on the page; false when there is none. */
    redo(): boolean;
    get canUndo(): boolean;
    get canRedo(): boolean;
    /** Takes a component's steps out (it left the page). */
    forget(owner: HistoryOwner): void;
    /** Called whenever what can be undone or redone may have changed. */
    on(listener: () => void): () => void;
    private emit;
}
/** The page's history, shared by its components. */
export declare const pageHistory: PageHistory;
