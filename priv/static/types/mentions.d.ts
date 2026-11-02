/** Someone a comment may mention, as Issho.Components.comments/1 lists them. */
export interface Candidate {
    key: string;
    name: string;
    kind?: string;
    color?: string | null;
    palette?: number;
    /** Whether they are in the room now. */
    here?: boolean;
}
/** The @ being typed before the caret, and what follows it: `null` when there is none. */
export declare function mentionQuery(text: string, caret: number): {
    start: number;
    query: string;
} | null;
/**
 * The candidates for a query: those whose name, or one of its words,
 * begins with it, ignoring case and accents; those in the room first,
 * then by name. At most `max`.
 */
export declare function matchCandidates(candidates: Candidate[], query: string, max?: number): Candidate[];
/** Whether a query is a whole name and the space after it: a mention written, not one being typed. */
export declare function finished(query: string, candidates: Candidate[]): boolean;
/** The text with the @ query replaced by the name, and where the caret goes. */
export declare function insertMention(text: string, start: number, caret: number, name: string): {
    text: string;
    caret: number;
};
/**
 * The picker of a text area: a list under it while an @ is typed, with the
 * keyboard of a list box (the arrows, Enter or Tab to pick, Escape). Each
 * pick's key is added to `keys`, the form's field of the mentions picked.
 * Gives a function that takes it away.
 */
export declare function mentionPicker(textarea: HTMLTextAreaElement, keys: HTMLInputElement, candidates: () => Candidate[]): () => void;
