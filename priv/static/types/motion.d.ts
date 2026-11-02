export type Motion = "full" | "reduced";
/** This person's motion: the app's word for it, else the browser's setting. */
export declare function motion(): Motion;
/** Says how much this person wants to see others move (`null`: as the browser says). */
export declare function setMotion(value: Motion | null): void;
/** Calls `listener` when this person's motion changes. Gives a function that stops it. */
export declare function onMotion(listener: (value: Motion) => void): () => void;
