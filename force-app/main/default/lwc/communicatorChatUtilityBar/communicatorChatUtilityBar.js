import { LightningElement, track } from 'lwc';
import getOrCreateThread            from '@salesforce/apex/CommunicatorChatController.getOrCreateThread';
import getUnreadCount               from '@salesforce/apex/CommunicatorChatController.getUnreadCount';
import markThreadAsRead             from '@salesforce/apex/CommunicatorChatController.markThreadAsRead';

const RECENT_STORAGE_KEY = 'comm_recent_opportunities';
const MAX_RECENT         = 5;
const POLL_INTERVAL_MS   = 6000;

export default class CommunicatorChatUtilityBar extends LightningElement {

    // ── State ──
    @track selectedRecordId   = null;
    @track threadId           = null;
    @track opportunityName    = '';
    @track showChat           = false;
    @track isLoadingThread    = false;
    @track loadError          = null;
    @track showSearch         = false;
    @track highlightMessageId = null;
    @track unreadCount        = 0;
    @track recentOpportunities = [];

    _pollTimer = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    connectedCallback() {
        this._loadRecent();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ─────────────────────────────────────────
    // Opportunity selection
    // ─────────────────────────────────────────

    handleOpportunitySelect(event) {
        const recordId = event.detail.recordId;
        if (!recordId) return;

        // lightning-record-picker doesn't give us the name directly,
        // we read it from the combobox label after selection
        const name = event.detail?.record?.fields?.Name?.value
                  || event.target?.label
                  || 'Opportunity';

        this._openChat(recordId, name);
    }

    handleRecentClick(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this._openChat(id, name);
    }

    handleBack() {
        this._stopPolling();
        this.showChat           = false;
        this.threadId           = null;
        this.selectedRecordId   = null;
        this.showSearch         = false;
        this.highlightMessageId = null;
        this.unreadCount        = 0;
        this.loadError          = null;
    }

    // ─────────────────────────────────────────
    // Thread loading
    // ─────────────────────────────────────────

    async _openChat(recordId, name) {
        this.isLoadingThread  = true;
        this.loadError        = null;
        this.selectedRecordId = recordId;
        this.opportunityName  = name;

        try {
            const thread   = await getOrCreateThread({ opportunityId: recordId });
            this.threadId  = thread.Id;
            this.showChat  = true;

            this._saveRecent(recordId, name);
            this._startPolling();

            await markThreadAsRead({ threadId: this.threadId });
            this.unreadCount = 0;
        } catch (err) {
            this.loadError = err.body?.message || err.message || 'Failed to open chat.';
            console.error('CommunicatorChatUtilityBar._openChat:', err);
        } finally {
            this.isLoadingThread = false;
        }
    }

    // ─────────────────────────────────────────
    // Chat handlers
    // ─────────────────────────────────────────

    handleToggleSearch() {
        this.showSearch = !this.showSearch;
        if (!this.showSearch) this.highlightMessageId = null;
    }

    handleNavigateToMessage(event) {
        this.highlightMessageId = event.detail.messageId;
        this.showSearch         = false;
        this.template.querySelector('c-communicator-chat-timeline')
            ?.scrollToMessage(event.detail.messageId);
    }

    handleMessageSent() {
        this.template.querySelector('c-communicator-chat-timeline')?.scrollToBottom();
        markThreadAsRead({ threadId: this.threadId }).catch(console.error);
        this.unreadCount = 0;
    }

    // ─────────────────────────────────────────
    // Polling
    // ─────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        this._pollTimer = setInterval(async () => {
            this.template.querySelector('c-communicator-chat-timeline')?.refresh();
            if (this.threadId) {
                try {
                    this.unreadCount = await getUnreadCount({ threadId: this.threadId });
                } catch (e) { /* silent */ }
            }
        }, POLL_INTERVAL_MS);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    // ─────────────────────────────────────────
    // Recent opportunities (localStorage)
    // ─────────────────────────────────────────

    _loadRecent() {
        try {
            const raw = localStorage.getItem(RECENT_STORAGE_KEY);
            this.recentOpportunities = raw ? JSON.parse(raw) : [];
        } catch (e) {
            this.recentOpportunities = [];
        }
    }

    _saveRecent(id, name) {
        try {
            // Remove if already present, then prepend
            let recent = this.recentOpportunities.filter(r => r.id !== id);
            recent.unshift({ id, name });
            if (recent.length > MAX_RECENT) recent = recent.slice(0, MAX_RECENT);
            this.recentOpportunities = recent;
            localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(recent));
        } catch (e) { /* silent */ }
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get hasRecent() {
        return this.recentOpportunities && this.recentOpportunities.length > 0;
    }

    get opportunityFilter() {
        return {
            criteria: [
                {
                    fieldPath: 'IsClosed',
                    operator:  'eq',
                    value:     false
                }
            ]
        };
    }
}
