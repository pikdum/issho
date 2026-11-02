import { Socket } from "phoenix";
/**
 * The rooms of a page lease a Phoenix socket per URL, each with its own
 * channel on it. A socket takes another room while it has no channel for
 * that room (Phoenix holds one channel per topic on a socket) and fewer
 * channels than the server's limit; otherwise the room gets a new socket.
 *
 * A socket belongs to its leases: it connects with the first, goes down and up
 * with the browser's offline and online events, and closes with the last
 * release. A room never disconnects it. A stuck room asks the lease to check
 * the socket: if the server answers a ping, that room alone recovers; if not,
 * the lease reconnects the socket once and every room on it recovers.
 *
 * (From Kotoba's collaboration, where it was written for its editors.)
 */
export interface Lease {
    readonly socket: Socket;
    check(): void;
    release(): void;
}
export declare function lease(url: string, topic: string, maxChannels: number, recover: () => void): Lease;
