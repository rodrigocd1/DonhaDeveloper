import { LightningElement, api, track } from 'lwc';
import getUnreadCount                    from '@salesforce/apex/CommunicatorChatController.getUnreadCount';

const POLL_INTERVAL_MS = 7000;
const MAX_DISPLAY      = 99;

export default class CommunicatorChatNotificationBadge extends LightningElement {

    @api threadId;

    @track unreadCount = 0;

    _pollTimer = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    connectedCallback() {
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
        }, POLL_INTERVAL_MS);
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
