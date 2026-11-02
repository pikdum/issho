declare const shapes: {
    readonly pause: '<rect x="14" y="4" width="4" height="16" rx="1"/><rect x="6" y="4" width="4" height="16" rx="1"/>';
    readonly play: '<polygon points="6 3 20 12 6 21 6 3"/>';
    readonly square: '<rect width="14" height="14" x="5" y="5" rx="2"/>';
    readonly check: '<path d="M20 6 9 17l-5-5"/>';
    readonly circle: '<circle cx="12" cy="12" r="9"/>';
    readonly minus: '<path d="M5 12h14"/>';
    readonly "chevron-down": '<path d="m6 9 6 6 6-6"/>';
};
export type IconName = keyof typeof shapes;
/** An icon, hidden from screen readers (its button says what it does). */
export declare function icon(name: IconName, className?: string): SVGSVGElement;
export {};
