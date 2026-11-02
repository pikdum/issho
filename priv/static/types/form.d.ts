/** A shared component in a form. */
export interface FormMember {
    /** Sends what it has and notes the accepted revision in its field; rejects with the reason it cannot. */
    flush(): Promise<unknown>;
    /** Locks (true) or unlocks (false) the component while the form waits. */
    lock(locked: boolean): void;
}
/**
 * Makes the form wait for the member on submit. Gives a function that
 * takes the member out (when the component goes). `failed` hears why a
 * submit could not go.
 */
export declare function holdForm(form: HTMLFormElement, member: FormMember, failed?: (reason: string) => void): () => void;
