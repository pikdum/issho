export interface Person {
    key: string;
    name: string | null;
    avatar: string | null;
    color: string | null;
    /** The theme's palette index (1 to 8) for a person with no colour. */
    palette: number;
    kind: "human" | "agent" | "service" | "guest";
    on_behalf_of: Person | null;
    joined_at: number;
    /** "write" when any of the person's tabs may write; "read" for someone only viewing. */
    can: "read" | "write";
}
type Meta = Omit<Person, "on_behalf_of"> & {
    on_behalf_of: Person | null;
    phx_ref?: string;
};
type PresenceState = Record<string, {
    metas: Meta[];
}>;
type PresenceDiff = {
    joins: PresenceState;
    leaves: PresenceState;
};
export type PresenceEvent = {
    type: "join" | "leave";
    person: Person;
} | {
    type: "change";
    people: Person[];
};
export declare class Presence {
    private readonly self;
    private state;
    private listeners;
    constructor(self: string);
    on(listener: (event: PresenceEvent) => void): () => void;
    /** Everyone in the room but this actor, in the order they joined. */
    get others(): Person[];
    /** Everyone in the room, this actor included. */
    get everyone(): Person[];
    /** The whole state, as the channel pushes it after a join (or a rejoin). */
    syncState(next: PresenceState): void;
    /** A diff: metas of tabs that joined and left. */
    syncDiff({ joins, leaves }: PresenceDiff): void;
    private announce;
    private emitChange;
    private emit;
}
export {};
