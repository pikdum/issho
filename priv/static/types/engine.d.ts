export type Json = null | boolean | number | string | Json[] | {
    [key: string]: Json;
};
export type State = {
    [key: string]: Json;
};
export type Operation = {
    [key: string]: Json;
};
export type Applied = {
    ok: true;
    state: State;
} | {
    ok: false;
    reason: string;
};
export interface Engine {
    /** The engine's name, as the server stores it: "map", "kotoba". */
    readonly name: string;
    readonly version: number;
    /** The state after a transaction's operations, all or none. */
    apply(state: State, ops: Operation[], author: string): Applied;
}
/** Makes an engine available to the documents that name it. */
export declare function registerEngine(engine: Engine): void;
export declare function engine(name: string): Engine;
