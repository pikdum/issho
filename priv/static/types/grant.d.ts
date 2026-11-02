export interface Grant {
    room: string;
    token: string;
    can: "read" | "write";
    /** The actor's key. */
    self: string;
    socket: string;
    max_channels: number;
}
/** What a LiveView hook has to push an event and read its reply. */
export interface LiveHook {
    pushEvent(event: string, payload: object, reply: (reply: unknown) => void): unknown;
}
/** Asks the hook's LiveView for a new grant for the room; rejects when it gives none. */
export declare function requestGrant(hook: LiveHook, room: string, timeout?: number): Promise<Grant>;
