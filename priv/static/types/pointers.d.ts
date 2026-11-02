import type { Peer } from "./awareness";
import type { Person } from "./presence";
export type PagePointer = {
    anchor: string;
    x: number;
    y: number;
    click?: number;
};
/** A pointer over a component that says what is under it (`point`): a place of its document. */
export type DocPointer = {
    doc: string;
    at: unknown;
    click?: number;
};
/** A pointer over a block of another room (its document): that room draws it. */
export type BlockPointer = {
    block: string;
};
/** The room of a document: the part of its id before the first `/`. */
export declare function roomOf(doc: string): string;
export interface Box {
    left: number;
    top: number;
    width: number;
    height: number;
}
/** A point in the viewport, and whether it is in it. */
export interface Spot {
    x: number;
    y: number;
    /** null in the viewport; else the edge of the viewport it is beyond. */
    edge: null | "top" | "bottom" | "left" | "right";
}
/** Someone the layer draws. */
export interface Pointing {
    key: string;
    name: string;
    color: string;
    kind: string;
    /** A pointer of the page, or the document an agent works in, and where in it. */
    pointer: PagePointer | null;
    doc: string | null;
    at?: unknown;
    /** The clicks of a pointer over a component (a place of its document), as a page pointer's. */
    click?: number;
    /** An agent's last gesture (Issho.Motion): how long its way there takes, and what it does there. */
    motion?: {
        gesture: string;
        ms: number;
        seq: number;
        fresh?: true;
    };
    /** An agent's place in a document, where it is drawn when the element it went to is not on this page. */
    place?: {
        doc: string;
        at: unknown;
        label?: string;
    };
    /** In a block of another room (`doc`): not drawn here, that room draws them. */
    away?: true;
}
/** Where a place of a document is in the viewport (its `at`), or `null`. */
export type Locator = (at: unknown) => Box | null;
/** The place of a document under a point of the viewport, or `null` (none it shares). */
export type Pointer = (clientX: number, clientY: number) => unknown;
/**
 * Says what place of the document of a component is under a point of the
 * screen: the element of the component (with `data-issho-doc`), and a
 * function of the point that gives the place, in the document's terms (a
 * point of a canvas, a cell of a grid). A person's pointer over it is that
 * place, which each browser draws where it is on its own screen (`locate`):
 * the same cell in another order, the same point of a canvas panned
 * elsewhere. Gives a function that takes it back.
 */
export declare function point(element: Element, pointer: Pointer): () => void;
/**
 * Says where the places of the document of a component are on the page: the
 * element of the component (with `data-issho-doc`), and a function of a
 * place's `at` that gives its box in the viewport (a caret, a node, a cell).
 * An agent's pointer goes there. Gives a function that takes it back.
 */
export declare function locate(element: Element, locator: Locator): () => void;
/** The point of a box, as fractions of it (rounded, so a state stays small). */
export declare function fractions(box: Box, x: number, y: number): {
    x: number;
    y: number;
};
/**
 * Where a pointer is in the viewport, from its anchor's box there: in it,
 * or held at its edge (`margin` inside it) with the side it is beyond.
 */
export declare function place(box: Box, pointer: {
    x: number;
    y: number;
}, viewport: {
    width: number;
    height: number;
}, margin?: number): Spot;
/** What a page heard of the agents' gestures in a frame. */
export interface Gestures {
    /** The sessions whose gesture this page has not seen before. */
    fresh: Set<string>;
    /** Each agent's session that made its last new gesture. */
    latest: Map<string, string>;
}
/**
 * Follows the sessions' gestures from frame to frame, so that each is new
 * once, for all that the page does with it (follow the agent, go along,
 * click, draw the way there). The gesture of a session that was in the
 * room when this page joined it (`wasThere`, the room's awareness says)
 * was made before the page came: it is where the agent already is, and is
 * not followed nor done again, however late the room's states reach the
 * page. A session that comes later is new with its first gesture.
 */
export declare function gestureTracker(): (peers: Peer[], wasThere: (session: string) => boolean) => Gestures;
/**
 * The others the layer draws: one each, the session that made the agent's
 * last gesture, else one that has a pointer (else one with a place, for an
 * agent), never this actor, and none whose pointer is in a component that
 * draws its own (`own`, the anchors inside one).
 */
export declare function pointing(peers: Peer[], everyone: Person[], self: string, gestures?: Gestures): Pointing[];
export declare function within(at: unknown): {
    x: number;
    y: number;
};
/** The anchor of an element: its own, or its nearest ancestor's. `null` where nothing is shared. */
export declare function anchorOf(target: Element | null): {
    anchor: string;
    element: Element;
} | "private" | "own" | null;
/** The element of an anchor on this page, or `null`. */
export declare function elementOf(anchor: string): Element | null;
/**
 * Where a place of a document is on this page: the box its component
 * locates (`locate`), or the component's own box when it locates none, or
 * `null` when the document is not on the page. For what a page draws at a
 * place: a pointer, a thread's marker.
 */
export declare function locatePlace(doc: string, at?: unknown): Box | null;
/**
 * This browser's pointer at a point of the viewport, over an element, for
 * the room `room` (any room's, when `null`).
 */
export declare function pointerAt(target: Element | null, clientX: number, clientY: number, room?: string | null): PagePointer | DocPointer | BlockPointer | null;
export interface PointerLayerOptions {
    /** Whether this browser shares its pointer (true); it sees the others' either way. */
    share?: boolean;
    /** The room of the page: whom it follows there, and what it says it shows. */
    room?: string;
    /** Says what changed in this browser's state: the room's `aware`. */
    aware: (changes: Record<string, unknown>) => void;
}
/**
 * Draws the others' pointers over the page, into `layer` (a fixed element
 * that covers the viewport and lets clicks through), and shares this
 * browser's. Over a component that says what is under a point of the
 * screen (`point`), a pointer is a place of its document, which each
 * browser draws where that place is on its own screen (`locate`): the
 * pointer goes from component to component as one. It keeps the one this
 * page follows on the screen, clicks the links and buttons they click that
 * take followers along (`data-issho-follow`), and tells the room what this
 * browser shows, so that agents move when someone sees them. Gives a
 * function that stops it; `draw` takes the others.
 */
export declare function pointerLayer(layer: HTMLElement, options: PointerLayerOptions): {
    draw: (people: Pointing[]) => void;
    stop: () => void;
};
