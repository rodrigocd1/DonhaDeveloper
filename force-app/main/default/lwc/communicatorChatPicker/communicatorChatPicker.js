import { LightningElement, api, track, wire } from 'lwc';
import getSettings   from '@salesforce/apex/CommunicatorChatController.getSettings';
import searchRecords from '@salesforce/apex/CommunicatorChatController.searchRecords';
import getRecordName from '@salesforce/apex/CommunicatorChatController.getRecordName';

const RECENT_STORAGE_KEY = 'comm_recent_records';
const DEBOUNCE_MS        = 350;
const MIN_KEYWORD_LEN    = 2;

// Standard icon map — fallback to standard:default for unknown objects
const OBJECT_ICON_MAP = {
    Opportunity:  'standard:opportunity',
    Account:      'standard:account',
    Case:         'standard:case',
    Contact:      'standard:contact',
    Lead:         'standard:lead',
    Contract:     'standard:contract',
    Order:        'standard:orders',
    Campaign:     'standard:campaign',
    Quote:        'standard:quote',
};

export default class CommunicatorChatPicker extends LightningElement {

    @api showCloseBtn = false;

    @track keyword          = '';
    @track searchResults    = [];
    @track isSearching      = false;
    @track isLoadingThread  = false;
    @track errorMessage     = null;
    @track recentRecords    = [];
    @track settings         = null;

    _debounceTimer  = null;
    _searched       = false;

    // ─────────────────────────────────────────
    // Wire — load settings once on mount
    // ─────────────────────────────────────────

    @wire(getSettings)
    wiredSettings({ data, error }) {
        if (data) {
            this.settings = data;
            this._loadRecent();
        }
        if (error) {
            console.error('CommunicatorChatPicker: failed to load settings', error);
            // Fallback — still load recent with defaults
            this._loadRecent();
        }
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    handleSearchInput(event) {
        this.keyword = event.target.value;
        this._debounceSearch();
    }

    handleSearchKeyDown(event) {
        if (event.key === 'Enter') {
            clearTimeout(this._debounceTimer);
            this._executeSearch();
        }
        if (event.key === 'Escape') {
            this.keyword       = '';
            this.searchResults = [];
            this._searched     = false;
        }
    }

    handleRecordSelect(event) {
        const id         = event.currentTarget.dataset.id;
        const name       = event.currentTarget.dataset.name;
        const objectType = event.currentTarget.dataset.objecttype;
        this._select(id, name, objectType);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ─────────────────────────────────────────
    // Search
    // ─────────────────────────────────────────

    _debounceSearch() {
        clearTimeout(this._debounceTimer);
        if (this.keyword.trim().length < MIN_KEYWORD_LEN) {
            this.searchResults = [];
            this._searched     = false;
            return;
        }
        this._debounceTimer = setTimeout(() => this._executeSearch(), DEBOUNCE_MS);
    }

    async _executeSearch() {
        const kw = this.keyword.trim();
        if (kw.length < MIN_KEYWORD_LEN) return;

        this.isSearching = true;
        this._searched   = false;
        try {
            const raw          = await searchRecords({ keyword: kw });
            this.searchResults = this._enrichResults(raw);
            this._searched     = true;
        } catch (err) {
            console.error('CommunicatorChatPicker._executeSearch:', err);
            this.searchResults = [];
        } finally {
            this.isSearching = false;
        }
    }

    _enrichResults(groups) {
        if (!groups) return [];
        return groups.map(g => ({
            ...g,
            iconName: OBJECT_ICON_MAP[g.objectApiName] || 'standard:default'
        }));
    }

    // ─────────────────────────────────────────
    // Selection
    // ─────────────────────────────────────────

    _select(recordId, name, objectType) {
        this._saveRecent(recordId, name, objectType);
        this.dispatchEvent(new CustomEvent('oppselected', {
            detail:   { recordId, name, objectType },
            bubbles:  false,
            composed: false
        }));
    }

    // ─────────────────────────────────────────
    // Recent records (localStorage)
    // ─────────────────────────────────────────

    _loadRecent() {
        try {
            const raw = localStorage.getItem(RECENT_STORAGE_KEY);
            const all = raw ? JSON.parse(raw) : [];
            const max = this.settings?.maxRecentRecords || 5;
            this.recentRecords = all.slice(0, max);
        } catch (e) {
            this.recentRecords = [];
        }
    }

    _saveRecent(id, name, objectType) {
        try {
            const max    = this.settings?.maxRecentRecords || 5;
            const stored = this._readAllRecent();
            const fresh  = stored.filter(r => r.id !== id);
            fresh.unshift({ id, name, objectType });
            const trimmed = fresh.slice(0, max);
            localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(trimmed));
            this.recentRecords = trimmed;
        } catch (e) { /* silencioso */ }
    }

    _readAllRecent() {
        try {
            const raw = localStorage.getItem(RECENT_STORAGE_KEY);
            return raw ? JSON.parse(raw) : [];
        } catch (e) {
            return [];
        }
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get searchPlaceholder() {
        if (!this.settings || !this.settings.objectApiNames) return 'Buscar registros...';
        const labels = this.settings.objectApiNames.join(', ');
        return `Buscar em: ${labels}`;
    }

    get hasSearchResults() {
        return this._searched && this.searchResults.length > 0;
    }

    get showNoResults() {
        return this._searched
            && !this.isSearching
            && this.searchResults.length === 0
            && this.keyword.trim().length >= MIN_KEYWORD_LEN;
    }

    get showRecent() {
        return !this._searched && this.recentRecords && this.recentRecords.length > 0;
    }
}
