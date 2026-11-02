import type { RoomTransport } from "./room";
export interface PhoenixTransportOptions {
    /** The socket's path or URL ("/issho/socket"). */
    socket?: string;
    /** The current join token. */
    token: string;
    /** Asks the server for a new token (through the LiveView). */
    renew?: () => Promise<string>;
    /** Milliseconds between renewals while the room is open (180000). */
    renewEvery?: number;
    /** The socket's `max_channels_per_transport` (100). */
    maxChannels?: number;
    /** Milliseconds a push waits for its reply (10000). */
    timeout?: number;
}
export declare function phoenixTransport(room: string, options: PhoenixTransportOptions): RoomTransport;
