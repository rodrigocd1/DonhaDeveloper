import { LightningElement, api, track } from 'lwc';
import getUnreadCount                    from '@salesforce/apex/CommunicatorChatController.getUnreadCount';

const DEFAULT_POLL_MS = 6000;
const MIN_POLL_MS     = 3000;
const MAX_DISPLAY     = 99;

export default class CommunicatorChatNotificationBadge extends LightningElement {

    @api threadId;

    @api
    get pollingIntervalMs() { return this._pollingIntervalMs; }
    set pollingIntervalMs(val) {
        const parsed = parseInt(val, 10);
        this._pollingIntervalMs = (!isNaN(parsed) && parsed >= MIN_POLL_MS) ? parsed : DEFAULT_POLL_MS;
        if (this._initialized) this._startPolling();
    }

    @track unreadCount = 0;

    _pollingIntervalMs = DEFAULT_POLL_MS;
    _pollTimer         = null;
    _initialized       = false;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    connectedCallback() {
        this._initialized = true;
        this._fetchCount();
        this._startPolling();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ─────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────

    @api
    async refresh() {
        await this._fetchCount();
    }

    // ─────────────────────────────────────────
    // Polling
    // ─────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        this._pollTimer = setInterval(() => {
            this._fetchCount().catch(console.error);
        }, this._pollingIntervalMs);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async _fetchCount() {
        if (!this.threadId) return;
        try {
            this.unreadCount = await getUnreadCount({ threadId: this.threadId });
        } catch (err) {
            console.error('CommunicatorChatNotificationBadge: failed to fetch unread count', err);
        }
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    handleClick() {
        this.dispatchEvent(new CustomEvent('badgeclick', {
            bubbles:  true,
            composed: true
        }));
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get hasUnread() {
        return this.unreadCount > 0;
    }

    get displayCount() {
        return this.unreadCount > MAX_DISPLAY ? `${MAX_DISPLAY}+` : String(this.unreadCount);
    }

    get unreadLabel() {
        return `${this.unreadCount} unread message${this.unreadCount !== 1 ? 's' : ''}`;
    }
}