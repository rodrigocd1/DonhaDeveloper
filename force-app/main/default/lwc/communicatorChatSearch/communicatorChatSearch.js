import { LightningElement, api, track } from 'lwc';
import searchMessages                    from '@salesforce/apex/CommunicatorChatController.searchMessages';

const DEBOUNCE_MS      = 350;
const MIN_KEYWORD_LEN  = 2;

export default class CommunicatorChatSearch extends LightningElement {

    @api threadId;

    @track keyword     = '';
    @track results     = [];
    @track isSearching = false;

    _debounceTimer = null;
    _searched      = false;

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    handleInput(event) {
        this.keyword = event.target.value;
        this._debounceSearch();
    }

    handleKeyDown(event) {
        if (event.key === 'Enter') {
            clearTimeout(this._debounceTimer);
            this._executeSearch();
        }
        if (event.key === 'Escape') {
            this.keyword  = '';
            this.results  = [];
            this._searched = false;
        }
    }

    handleResultClick(event) {
        const messageId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('navigatemessage', {
            detail:  { messageId },
            bubbles: true,
            composed: true
        }));
    }

    // ─────────────────────────────────────────
    // Search
    // ─────────────────────────────────────────

    _debounceSearch() {
        clearTimeout(this._debounceTimer);
        if (this.keyword.trim().length < MIN_KEYWORD_LEN) {
            this.results   = [];
            this._searched = false;
            return;
        }
        this._debounceTimer = setTimeout(() => {
            this._executeSearch();
        }, DEBOUNCE_MS);
    }

    async _executeSearch() {
        const kw = this.keyword.trim();
        if (kw.length < MIN_KEYWORD_LEN) return;

        this.isSearching = true;
        this._searched   = false;
        try {
            const raw       = await searchMessages({ threadId: this.threadId, keyword: kw });
            this.results    = this._enrichResults(raw, kw);
            this._searched  = true;
        } catch (err) {
            console.error('CommunicatorChatSearch error:', err);
            this.results = [];
        } finally {
            this.isSearching = false;
        }
    }

    // ─────────────────────────────────────────
    // renderedCallback - inject highlighted HTML
    // ─────────────────────────────────────────

    renderedCallback() {
        if (!this.keyword) return;
        this.results.forEach(r => {
            const el = this.template.querySelector(`p.comm-search__result-body[data-id="${r.Id}"]`);
            if (el) {
                el.innerHTML = this._highlightKeyword(r.Body__c || '', this.keyword);
            }
        });
    }

    // ─────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────

    _enrichResults(msgs, keyword) {
        return msgs.map(m => ({
            ...m,
            senderName:    m.Sender__r?.Name || 'Unknown',
            formattedTime: m.SentAt__c ? new Date(m.SentAt__c).toLocaleString() : ''
        }));
    }

    _highlightKeyword(text, keyword) {
        if (!text || !keyword) return this._escapeHtml(text);
        const escaped    = this._escapeHtml(text);
        const escapedKw  = keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const regex      = new RegExp(`(${escapedKw})`, 'gi');
        return escaped.replace(regex, '<mark class="comm-search__highlight">$1</mark>');
    }

    _escapeHtml(text) {
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get hasResults() {
        return this.results.length > 0;
    }

    get showNoResults() {
        return this._searched && !this.isSearching && this.results.length === 0 && this.keyword.trim().length >= MIN_KEYWORD_LEN;
    }

    get resultCountLabel() {
        const n = this.results.length;
        return `${n} result${n !== 1 ? 's' : ''} found`;
    }
}
