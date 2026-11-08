import { LightningElement, api, track } from 'lwc';
import getMentionCandidates from '@salesforce/apex/CommunicatorChatController.getMentionCandidates';

const DEBOUNCE_MS = 250;

export default class CommunicatorChatMention extends LightningElement {

    @api threadId;

    @track keyword = '';
    @track candidates = [];

    _debounceTimer = null;

    connectedCallback() {
        this._load('');
        // Focus input after render
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.template.querySelector('.comm-mention__input')?.focus();
        }, 50);
    }

    handleInput(event) {
        this.keyword = event.target.value;
        clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => this._load(this.keyword), DEBOUNCE_MS);
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.dispatchEvent(new CustomEvent('close'));
        }
    }

    handleSelect(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        const type = event.currentTarget.dataset.type;
        this.dispatchEvent(new CustomEvent('mentionselect', {
            detail: { id, name, type },
            bubbles: false, composed: false
        }));
    }

    async _load(kw) {
        try {
            this.candidates = await getMentionCandidates({
                threadId: this.threadId,
                keyword:  kw
            });
        } catch (e) {
            this.candidates = [];
        }
    }

    get users() {
        return this.candidates.filter(c => c.candidateType === 'User');
    }

    get groups() {
        return this.candidates.filter(c => c.candidateType === 'Group');
    }

    get hasUsers()  { return this.users.length  > 0; }
    get hasGroups() { return this.groups.length > 0; }
    get showEmpty() {
        return this.candidates.length === 0 && this.keyword.length > 0;
    }
}