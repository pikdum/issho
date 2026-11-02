import { type LiveHook } from "./grant";
import { commentMarkers } from "./comments";
interface Hook extends LiveHook {
    el: HTMLElement;
}
interface PeopleHook extends Hook {
    stop?: () => void;
    room?: string;
}
interface MotionHook extends Hook {
    stop?: () => void;
}
interface CommentsHook extends Hook {
    markers?: ReturnType<typeof commentMarkers>;
    focused?: string | null;
    pickers?: Map<HTMLTextAreaElement, () => void>;
    handleEvent(event: string, callback: (payload: never) => void): void;
    pushEventTo(target: HTMLElement, event: string, payload: unknown): void;
}
export declare const Hooks: {
    IsshoPeople: {
        mounted(this: PeopleHook): void;
        destroyed(this: PeopleHook): void;
    };
    IsshoPointers: {
        mounted(this: PeopleHook): void;
        destroyed(this: PeopleHook): void;
    };
    IsshoMotion: {
        mounted(this: MotionHook): void;
        destroyed(this: MotionHook): void;
    };
    IsshoComments: {
        mounted(this: CommentsHook): void;
        updated(this: CommentsHook): void;
        destroyed(this: CommentsHook): void;
    };
    IsshoAgents: {
        mounted(this: PeopleHook): void;
        destroyed(this: PeopleHook): void;
    };
};
export {};
