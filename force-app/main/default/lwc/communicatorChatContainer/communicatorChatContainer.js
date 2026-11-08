import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOrCreateThread from '@salesforce/apex/CommunicatorChatController.getOrCreateThread';
import markThreadAsRead  from '@salesforce/apex/CommunicatorChatController.markThreadAsRead';
import getSettings       from '@salesforce/apex/CommunicatorChatController.getSettings';
import CommunicatorChatHistoryModal from 'c/communicatorChatHistoryModal';

const DEFAULT_POLL_MS = 6000;
const MIN_POLL_MS     = 3000;

export default class CommunicatorChatContainer extends NavigationMixin(LightningElement) {

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
    _pollIntervalMs = DEFAULT_POLL_MS;
    _initialized    = false;

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
            await this._loadConfig();
            const thread   = await getOrCreateThread({ recordId: this.recordId, objectType: '' });
            this._threadId = thread.Id;
            this._onThreadReady();
        } catch (err) {
            this.errorMessage = err.body?.message || err.message || 'Failed to initialize chat.';
            console.error('CommunicatorChatContainer._initThread:', err);
        } finally {
            this.isLoading = false;
        }
    }

    async _loadConfig() {
        try {
            const settings = await getSettings();
            if (settings.pollingIntervalMs >= MIN_POLL_MS) {
                this._pollIntervalMs = settings.pollingIntervalMs;
            }
        } catch (e) {
            // Keep default on failure
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
        }, this._pollIntervalMs);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    handleToggleHistory() {
        CommunicatorChatHistoryModal.open({
            size:     'large',
            recordId: this.recordId
        }).then(result => {
            if (!result) return;
            if (result.action === 'navigateToRecord') {
                const targetObjectApiName = result.objectType || 'Opportunity';
                if (this._isOpportunityRecord(result.recordId, targetObjectApiName) && this._isBrokerCommunityContext()) {
                    this._navigateToBrokerCommunityDetail(result.recordId);
                    return;
                }
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId:      result.recordId,
                        objectApiName: targetObjectApiName,
                        actionName:    'view'
                    }
                });
            } else if (result.action === 'navigateToAr') {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId:   result.arId,
                        actionName: 'view'
                    }
                });
            }
        });
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
        const messageId = event.detail?.messageId;
        if (!messageId) return;
        this.showSearch = false;
        // navigateToMessage loads the correct page if the message isn't in the current view
        this.template.querySelector('c-communicator-chat-timeline')?.navigateToMessage(messageId);
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

    get headerTitle() {
        return 'Chat';
    }

    _isOpportunityRecord(recordId, objectApiName) {
        const normalizedObjectApiName = String(objectApiName || '').trim().toLowerCase();
        const normalizedRecordId = String(recordId || '').trim();
        return normalizedObjectApiName === 'opportunity' || normalizedRecordId.startsWith('006');
    }

    _isBrokerCommunityContext() {
        const pathname = (window.location?.pathname || '').toLowerCase();
        const hostname = (window.location?.hostname || '').toLowerCase();
        return hostname.includes('.my.site.com')
            || pathname.includes('/corretores')
            || pathname.includes('/s/')
            || pathname.includes('/kanban');
    }

    _navigateToBrokerCommunityDetail(recordId) {
        const pathname = String(window.location?.pathname || '');
        const basePath = pathname.includes('/s/') ? pathname.split('/s/')[0] : pathname;
        const normalizedBasePath = basePath
            .replace(/\/kanban.*$/i, '')
            .replace(/\/+$/, '')
            .replace(/\/corretores$/i, '');
        window.open(`${normalizedBasePath}/corretores/s/detail/${recordId}`, '_blank');
    }
}