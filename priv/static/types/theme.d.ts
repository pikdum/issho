import type { Someone } from "./people";
import type { Pointing } from "./pointers";
export interface Look {
    /** A person of the list: what shows in their item, in place of the avatar. */
    person?: (someone: Someone) => Node | null;
    /** A pointer over the page: what shows at the point, in place of the arrow and the name. */
    pointer?: (pointing: Pointing) => Node | null;
}
/** Sets how Issho's pieces of a page look; each call merges into the last. */
export declare function configure(changes: Look): void;
/** How the app said Issho's pieces look. */
export declare function currentLook(): Look;
