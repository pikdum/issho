import type { Engine, Json } from "../engine";
/** A comment of a thread, as the comments document keeps it. */
export interface Comment {
    id: string;
    author: {
        key: string;
        name: string | null;
        kind?: string;
        avatar?: string | null;
        color?: string | null;
        on_behalf_of?: {
            key: string;
            name: string | null;
        } | null;
    };
    body: string;
    mentions: string[];
    at: string;
    edited: string | null;
    reactions: {
        [emoji: string]: string[];
    };
}
/** A thread of comments, at a place of a component or of the page. */
export interface Thread {
    id: string;
    place: {
        doc: string;
        at?: Json;
        label?: string;
    } | null;
    status: "open" | "resolved";
    resolved: {
        by: string;
        at: string;
    } | null;
    comments: Comment[];
}
export declare const commentsEngine: Engine;
