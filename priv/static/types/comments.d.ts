import { type Box } from "./pointers";
/** A thread the page marks: where it is, and what its mark says. */
export interface Marked {
    id: string;
    place: {
        doc: string;
        at?: unknown;
        label?: string;
    };
    /** Its comments, the number on the mark. */
    count: number;
    /** What a screen reader says of it: "3 comments, Ada: Should this go first?". */
    label: string;
    /** The colour of whoever began it. */
    color?: string | null;
    palette?: number;
}
export interface MarkersOptions {
    /** A mark clicked, or chosen from the keyboard. */
    open: (thread: string) => void;
    /** Where a place is on this page; `locatePlace` unless given (tests). */
    locate?: (doc: string, at?: unknown) => Box | null;
}
/**
 * Where a thread's mark goes for its place's box: at the box's top right
 * corner, in the viewport; `null` when the box is not on the screen.
 */
export declare function markSpot(box: Box, viewport: {
    width: number;
    height: number;
}, size?: number): {
    x: number;
    y: number;
} | null;
/**
 * A layer of marks over the page, one for each thread with a place on it.
 * `draw` takes the threads; it follows the page as it scrolls and as the
 * components' content moves under the marks.
 */
export declare function commentMarkers(options: MarkersOptions): {
    draw: (threads: Marked[], focused?: string | null) => void;
    stop: () => void;
};
