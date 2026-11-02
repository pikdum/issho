import type { Peer } from "./awareness";
import type { Person } from "./presence";
export interface PeopleOptions {
    /** How many avatars before "+N" (8). */
    max?: number;
    /** The list's accessible name ("People here"). */
    label?: string;
    /** The room the list is of: a click on someone follows them there. Without it, no one is followed. */
    room?: string;
}
/** The view of the people the list draws: a person and what they are doing. */
export interface Someone {
    person: Person;
    status: string | null;
    you: boolean;
}
/** The people of the room as the list shows them: this actor first, then in the order they came. */
export declare function someone(everyone: Person[], peers: Peer[], self: string): Someone[];
/** Draws the people into an element, replacing what it held. */
export declare function drawPeople(element: HTMLElement, people: Someone[], options?: PeopleOptions): void;
/** One line about someone: "Claude Code, an agent for Ada: Renaming". */
export declare function describe({ person, status, you }: Someone): string;
