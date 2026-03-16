import { LightningElement, api, track } from 'lwc';
import getOrCreateThread from '@salesforce/apex/CommunicatorChatController.getOrCreateThread';
import markThreadAsRead  from '@salesforce/apex/CommunicatorChatController.markThreadAsRead';

const POLL_INTERVAL_MS = 5000;

export default class CommunicatorChatContainer extends LightningElement {

    @api recordId;

    // threadId can be passed directly from parent (communicatorChatFloatingButton)
    // to avoid a redundant Apex call. If not passed, it is resolved internally.
    @api
    get threadId() { return this._threadId; }
    set threadId(val) {
        this._threadId = val;
        if (val && !this._initialized) {
            this._onThreadReady();
        }
    }

    @track _threadId;
    @track isLoading        = true;
    @track showSearch       = false;
    @track isMaximized      = false;
    @track highlightMessageId;
    @track errorMessage     = null;

    _pollTimer;
    _initialized = false;

    connectedCallback() {
        // If threadId was already set via @api before connectedCallback, _onThreadReady
        // was already called in the setter. Only init here if threadId not yet set.
        if (!this._threadId) {
            this._initThread();
        }
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    async _initThread() {
        if (!this.recordId) {
            this.errorMessage = 'Record ID not available.';
            this.isLoading = false;
            return;
        }
        try {
            this.isLoading = true;
            const thread   = await getOrCreateThread({ opportunityId: this.recordId });
            this._threadId = thread.Id;
            this._onThreadReady();
        } catch (err) {
            this.errorMessage = err.body?.message || err.message || 'Failed to initialize chat.';
            console.error('CommunicatorChatContainer._initThread:', err);
        } finally {
            this.isLoading = false;
        }
    }

    _onThreadReady() {
        this._initialized = true;
        this.isLoading    = false;
        markThreadAsRead({ threadId: this._threadId }).catch(console.error);
        this._startPolling();
    }

    _startPolling() {
        this._stopPolling();
        this._pollTimer = setInterval(() => {
            this.template.querySelector('c-communicator-chat-timeline')?.refresh();
            this.template.querySelector('c-communicator-chat-notification-badge')?.refresh();
        }, POLL_INTERVAL_MS);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    handleToggleSearch() {
        this.showSearch = !this.showSearch;
        if (!this.showSearch) this.highlightMessageId = null;
    }

    handleToggleMaximize() {
        this.isMaximized = !this.isMaximized;
    }

    handleMessageSent() {
        this.template.querySelector('c-communicator-chat-timeline')?.scrollToBottom();
        markThreadAsRead({ threadId: this._threadId }).catch(console.error);
    }

    handleNavigateToMessage(event) {
        this.highlightMessageId = event.detail.messageId;
        this.showSearch         = false;
        this.template.querySelector('c-communicator-chat-timeline')?.scrollToMessage(event.detail.messageId);
    }

    get containerClass() {
        return ['comm-chat', this.isMaximized ? 'comm-chat--maximized' : 'comm-chat--normal'].join(' ');
    }

    get maximizeIcon() {
        return this.isMaximized ? 'utility:contract_alt' : 'utility:expand_alt';
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showContent() {
        return !this.isLoading && !this.errorMessage && !!this._threadId;
    }
}
