import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getThreadByRecord from '@salesforce/apex/InteractionChatController.getThreadByRecord';
import getMessages       from '@salesforce/apex/InteractionChatController.getMessages';

export default class ChatTimelinePanel extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    @track thread    = null;
    @track messages  = [];
    @track isLoading = false;
    @track errorMsg  = '';

    _limit = 20;

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadTimeline();
    }

    // ─── Load ────────────────────────────────────────────────────────────────

    async _loadTimeline() {
        this.isLoading = true;
        this.errorMsg  = '';
        try {
            const t = await getThreadByRecord({ recordId: this.recordId });
            if (t) {
                this.thread   = t;
                await this._fetchMessages();
            }
        } catch (e) {
            this.errorMsg = this._extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async _fetchMessages() {
        try {
            const msgs = await getMessages({ threadId: this.thread.id, limitSize: this._limit });
            // Timeline shows newest first
            this.messages = [...msgs].reverse().map(m => ({
                ...m,
                isUserMessage:  m.messageType === 'UserMessage',
                isStatusChange: m.messageType === 'StatusChange',
                isFile:         m.messageType === 'File',
                formattedDate:  m.createdDate
                    ? new Date(m.createdDate).toLocaleString('pt-BR')
                    : ''
            }));
        } catch (e) {
            this.errorMsg = this._extractError(e);
        }
    }

    // ─── Handlers ────────────────────────────────────────────────────────────

    async handleLoadMore() {
        this._limit += 20;
        this.isLoading = true;
        try {
            await this._fetchMessages();
        } finally {
            this.isLoading = false;
        }
    }

    handleFileClick(e) {
        e.preventDefault();
        const docId = e.currentTarget.dataset.docid;
        if (!docId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: docId }
        });
    }

    // ─── Helper ──────────────────────────────────────────────────────────────

    _extractError(e) {
        if (e && e.body && e.body.message) return e.body.message;
        if (e && e.message) return e.message;
        return 'Erro desconhecido.';
    }
}
