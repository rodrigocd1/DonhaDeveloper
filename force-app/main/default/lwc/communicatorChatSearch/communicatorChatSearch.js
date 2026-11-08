import { LightningElement, api, track } from 'lwc';
import searchMessages                    from '@salesforce/apex/CommunicatorChatController.searchMessages';
import searchMessagesAcrossThreads       from '@salesforce/apex/CommunicatorChatController.searchMessagesAcrossThreads';

const DEBOUNCE_MS     = 350;
const MIN_KEYWORD_LEN = 2;
const SEARCH_MODE_APEX = 'apex';
const SEARCH_MODE_EXTERNAL = 'external';

export default class CommunicatorChatSearch extends LightningElement {

    @api threadId;
    @api threadIds;       // array of Ids — enables cross-thread search in history page
    @api stageByThread;   // object { [threadId]: stageName } — enriches results with stage label
    @api searchMode = SEARCH_MODE_APEX;
    @api placeholder = 'Buscar mensagens...';
    @api externalResults = [];
    @api externalSearchComplete = false;
    @api externalIsSearching = false;

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
        if (this.isExternalSearchMode) {
            this._debounceExternalSearchChange();
            return;
        }
        this._debounceSearch();
    }

    handleKeyDown(event) {
        if (event.key === 'Enter') {
            if (this.isExternalSearchMode) {
                this._notifySearchChange();
                return;
            }
            clearTimeout(this._debounceTimer);
            this._executeSearch();
        }
        if (event.key === 'Escape') {
            this.keyword   = '';
            this.results   = [];
            this._searched = false;
            if (this.isExternalSearchMode) {
                clearTimeout(this._debounceTimer);
                this._notifySearchChange();
            }
        }
    }

    handleResultClick(event) {
        const messageId = event.currentTarget.dataset.id;
        const threadId  = event.currentTarget.dataset.threadId;
        this.dispatchEvent(new CustomEvent('navigatemessage', {
            detail:   { messageId, threadId },
            bubbles:  true,
            composed: true
        }));
    }

    // ─────────────────────────────────────────
    // Busca com debounce
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

    _debounceExternalSearchChange() {
        clearTimeout(this._debounceTimer);
        if (this.keyword.trim().length < MIN_KEYWORD_LEN) {
            this._notifySearchChange();
            return;
        }
        this._debounceTimer = setTimeout(() => {
            this._notifySearchChange();
        }, DEBOUNCE_MS);
    }

    async _executeSearch() {
        const kw = this.keyword.trim();
        if (kw.length < MIN_KEYWORD_LEN) return;

        this.isSearching = true;
        this._searched   = false;
        try {
            const isMultiThread = Array.isArray(this.threadIds) && this.threadIds.length > 0;
            const raw = isMultiThread
                ? await searchMessagesAcrossThreads({ threadIds: this.threadIds, keyword: kw })
                : await searchMessages({ threadId: this.threadId, keyword: kw });
            this.results   = this._enrichResults(raw);
            this._searched = true;
        } catch (err) {
            console.error('CommunicatorChatSearch._executeSearch:', err);
            this.results = [];
        } finally {
            this.isSearching = false;
        }
    }

    // ─────────────────────────────────────────
    // renderedCallback — injeta highlight no corpo
    // ─────────────────────────────────────────

    renderedCallback() {
        const results = this.displayedResults;
        if (!this.keyword || results.length === 0) return;
        results.forEach(r => {
            // Seletor consistente com o HTML: comm-search__item-body
            const el = this.template.querySelector(`p.comm-search__item-body[data-id="${r.Id}"]`);
            if (el) {
                // eslint-disable-next-line @lwc/lwc/no-inner-html
                el.innerHTML = this._highlightKeyword(r.Body__c || r.previewText || '', this.keyword);
            }
        });
    }

    // ─────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────

    _enrichResults(msgs) {
        const stageMap = this.stageByThread || {};
        return msgs.map(m => ({
            ...m,
            senderName:    m.Sender__r?.Name || m.CreatedBy?.Name || 'Desconhecido',
            formattedTime: m.SentAt__c
                ? new Date(m.SentAt__c).toLocaleString('pt-BR')
                : '',
            stageName:     stageMap[m.Thread__c] || ''
        }));
    }

    _highlightKeyword(text, keyword) {
        if (!text || !keyword) return this._escapeHtml(text);
        const escaped   = this._escapeHtml(text);
        const escapedKw = keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const regex     = new RegExp(`(${escapedKw})`, 'gi');
        return escaped.replace(regex, '<mark class="comm-search__highlight">$1</mark>');
    }

    _escapeHtml(text) {
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    _notifySearchChange() {
        this.dispatchEvent(new CustomEvent('searchchange', {
            detail: { keyword: this.keyword },
            bubbles: true,
            composed: true
        }));
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get hasResults() {
        return this.displayedResults.length > 0;
    }

    get isExternalSearchMode() {
        return this.searchMode === SEARCH_MODE_EXTERNAL;
    }

    get displayedResults() {
        return this.isExternalSearchMode
            ? (Array.isArray(this.externalResults) ? this.externalResults : [])
            : this.results;
    }

    get showSpinner() {
        return this.isExternalSearchMode ? this.externalIsSearching : this.isSearching;
    }

    get showNoResults() {
        if (this.keyword.trim().length < MIN_KEYWORD_LEN) {
            return false;
        }

        if (this.isExternalSearchMode) {
            return this.externalSearchComplete
                && !this.externalIsSearching
                && this.displayedResults.length === 0;
        }

        return this._searched
            && !this.isSearching
            && this.displayedResults.length === 0;
    }

    get resultCountLabel() {
        const n = this.displayedResults.length;
        return `${n} resultado${n !== 1 ? 's' : ''} encontrado${n !== 1 ? 's' : ''}`;
    }
}