import { LightningElement, api, track } from 'lwc';
import getMessages                       from '@salesforce/apex/CommunicatorChatController.getMessages';
import getMessageCount                   from '@salesforce/apex/CommunicatorChatController.getMessageCount';
import pollNewMessages                   from '@salesforce/apex/CommunicatorChatController.pollNewMessages';
import Id                                from '@salesforce/user/Id';

const PAGE_SIZE          = 20;
const SCROLL_THRESHOLD   = 80; // px from top to trigger load more
const POLL_INTERVAL_MS   = 5000;

export default class CommunicatorChatTimeline extends LightningElement {

    @api threadId;
    @api
    get highlightMessageId() { return this._highlightMessageId; }
    set highlightMessageId(val) {
        this._highlightMessageId = val;
        if (val) this._applyHighlight(val);
    }

    @track messages       = [];
    @track isLoadingMore  = false;
    @track hasMoreMessages = false;

    _currentOffset  = 0;
    _totalCount     = 0;
    _lastTimestamp  = null;
    _pollTimer      = null;
    _highlightMessageId;
    _currentUserId  = Id;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    async connectedCallback() {
        await this._loadInitial();
        this._startPolling();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    renderedCallback() {
        this._renderMessageBodies();
    }

    // ─────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────

    @api
    async refresh() {
        await this._pollMessages();
    }

    @api
    scrollToBottom() {
        const bottom = this.template.querySelector('.comm-timeline__bottom');
        if (bottom) bottom.scrollIntoView({ behavior: 'smooth' });
    }

    @api
    scrollToMessage(messageId) {
        const el = this.template.querySelector(`[data-message-id="${messageId}"]`);
        if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            this._applyHighlight(messageId);
        }
    }

    @api
    async loadNextPage() {
        if (this._currentOffset >= this._totalCount || this.isLoadingMore) return;
        await this._loadPage(this._currentOffset);
    }

    // ─────────────────────────────────────────
    // Data loading
    // ─────────────────────────────────────────

    async _loadInitial() {
        this._totalCount    = await getMessageCount({ threadId: this.threadId });
        this._currentOffset = Math.max(0, this._totalCount - PAGE_SIZE);
        const msgs = await getMessages({ threadId: this.threadId, pageSize: PAGE_SIZE, offsetVal: this._currentOffset });
        this.messages       = this._enrichMessages(msgs);
        this.hasMoreMessages = this._currentOffset > 0;
        this._updateLastTimestamp();

        // Give DOM time to render then scroll to bottom
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.scrollToBottom(), 100);
    }

    async _loadPage(offset) {
        if (this.isLoadingMore) return;
        this.isLoadingMore = true;
        try {
            const containerEl    = this.template.querySelector('.comm-timeline');
            const prevScrollHeight = containerEl?.scrollHeight || 0;

            const msgs = await getMessages({ threadId: this.threadId, pageSize: PAGE_SIZE, offsetVal: offset });
            const enriched = this._enrichMessages(msgs);

            // Prepend older messages
            this.messages       = [...enriched, ...this.messages];
            this._currentOffset = offset;
            this.hasMoreMessages = this._currentOffset > 0;

            // Restore scroll position after DOM update
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const newScrollHeight = containerEl?.scrollHeight || 0;
                if (containerEl) {
                    containerEl.scrollTop = newScrollHeight - prevScrollHeight;
                }
            }, 50);
        } finally {
            this.isLoadingMore = false;
        }
    }

    async _pollMessages() {
        if (!this._lastTimestamp) return;
        const newMsgs = await pollNewMessages({
            threadId:      this.threadId,
            lastTimestamp: this._lastTimestamp
        });
        if (newMsgs && newMsgs.length > 0) {
            this.messages = [...this.messages, ...this._enrichMessages(newMsgs)];
            this._updateLastTimestamp();
            this.scrollToBottom();
        }
    }

    // ─────────────────────────────────────────
    // Polling
    // ─────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        this._pollTimer = setInterval(() => {
            this._pollMessages().catch(console.error);
        }, POLL_INTERVAL_MS);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    handleScroll(event) {
        const el = event.target;
        if (el.scrollTop <= SCROLL_THRESHOLD && this.hasMoreMessages && !this.isLoadingMore) {
            const newOffset = Math.max(0, this._currentOffset - PAGE_SIZE);
            this._loadPage(newOffset).catch(console.error);
        }
    }

    // ─────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────

    _enrichMessages(msgs) {
        return msgs.map(m => ({
            ...m,
            senderName:    m.Sender__r?.Name || 'Unknown',
            senderPhoto:   m.Sender__r?.SmallPhotoUrl || '/img/icon/t4v35/standard/person_account_120.png',
            formattedTime: m.SentAt__c ? new Date(m.SentAt__c).toLocaleString() : '',
            attachmentUrl: m.ContentDocumentId__c
                ? `/sfc/servlet.shepherd/document/download/${m.ContentDocumentId__c}`
                : null,
            bubbleClass:   this._buildBubbleClass(m),
            _highlighted:  false
        }));
    }

    _buildBubbleClass(msg) {
        const isMine = msg.Sender__c === this._currentUserId;
        return ['comm-msg', isMine ? 'comm-msg--mine' : 'comm-msg--theirs'].join(' ');
    }

    _updateLastTimestamp() {
        if (this.messages.length > 0) {
            const last = this.messages[this.messages.length - 1];
            this._lastTimestamp = last.SentAt__c;
        }
    }

    _renderMessageBodies() {
        this.messages.forEach(msg => {
            if (!msg.Body__c) return;
            const el = this.template.querySelector(`p[data-id="${msg.Id}"]`);
            if (el) {
                // Safe: Body__c is plain text stored in Salesforce, not HTML
                el.textContent = msg.Body__c;
            }
        });
    }

    _applyHighlight(messageId) {
        // Remove previous highlights
        this.template.querySelectorAll('.comm-msg--highlighted').forEach(el => {
            el.classList.remove('comm-msg--highlighted');
        });
        const el = this.template.querySelector(`[data-message-id="${messageId}"]`);
        if (el) {
            el.classList.add('comm-msg--highlighted');
        }
    }

    get isEmpty() {
        return !this.isLoadingMore && this.messages.length === 0;
    }
}
