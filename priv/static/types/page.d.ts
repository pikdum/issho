import { type PhoenixTransportOptions } from "./phoenix";
import { Room, type RoomOptions } from "./room";
/**
 * The room of a page, joined once however many components ask for it.
 * `options.token` is the join token your LiveView signed
 * (`Issho.Token.sign/4`, or a grant's), and `options.self` the actor's
 * key. Release it with `releaseRoom` when the component goes.
 */
export declare function joinRoom(room: string, options: PhoenixTransportOptions & RoomOptions): Promise<Room>;
/** Lets go of a room a component asked for; the page leaves it when no component holds it. */
export declare function releaseRoom(room: string): Promise<void>;
