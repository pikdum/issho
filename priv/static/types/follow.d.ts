/** The key of the one followed in a room, or `null`. */
export declare function following(room: string): string | null;
/** Follows someone in a room, by their key, or stops (`null`). */
export declare function follow(room: string, key: string | null): void;
/** Calls `listener` when someone else is followed in a room, or no one. Gives a function that stops it. */
export declare function onFollow(room: string, listener: (key: string | null) => void): () => void;
/**
 * Stops following in a room when the person goes their own way in an
 * element (the page, a block): scrolls, presses, or types. Gives a function
 * that stops it.
 */
export declare function stopOnOwnWay(room: string, element?: Document | HTMLElement): () => void;
