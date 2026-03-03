import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getThreadByRecord        from '@salesforce/apex/InteractionChatController.getThreadByRecord';
import getOrCreateThread        from '@salesforce/apex/InteractionChatController.getOrCreateThread';
import getMessages              from '@salesforce/apex/InteractionChatController.getMessages';
import getMessagesSince         from '@salesforce/apex/InteractionChatController.getMessagesSince';
import postMessage              from '@salesforce/apex/InteractionChatController.postMessage';
import changeStatus             from '@salesforce/apex/InteractionChatController.changeStatus';
import linkUploadedFileToThread from '@salesforce/apex/InteractionChatController.linkUploadedFileToThread';

const POLL_INTERVAL_MS = 6000;

export default class ChatMessagePanel extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @api isInternal = false;
    @api title;

    @track thread        = null;
    @track messages      = [];
    @track isLoading     = false;
    @track isSending     = false;
    @track errorMsg      = '';

    // Form fields
    reason         = '';
    initialMessage = '';
    messageBody    = '';
    newStatus      = '';

    // Polling
    _pollTimer   = null;
    _lastMsgDate = null;

    acceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg', '.docx', '.xlsx', '.txt'];

    get showInitForm()   { return !this.thread && !this.isLoading; }
    get threadIsOpen()   { return this.thread && !this.thread.isClosed; }
    get threadIsClosed() { return this.thread && !!this.thread.isClosed; }

    reasonOptions = [
        { label: 'Suporte',      value: 'Suporte' },
        { label: 'Dúvida',       value: 'Dúvida' },
        { label: 'Reclamação',   value: 'Reclamação' },
        { label: 'Comercial',    value: 'Comercial' },
    ];

    statusOptions = [
        { label: 'Open',    value: 'Open' },
        { label: 'Pending', value: 'Pending' },
        { label: 'Closed',  value: 'Closed' },
    ];

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadThread();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ─── Load / Polling ──────────────────────────────────────────────────────

    async _loadThread() {
        this.isLoading = true;
        this.errorMsg  = '';
        try {
            const t = await getThreadByRecord({ recordId: this.recordId });
            if (t) {
                this.thread    = t;
                this.newStatus = t.status;
                await this._loadMessages();
                this._startPolling();
            }
        } catch (e) {
            this.errorMsg = this._extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async _loadMessages() {
        try {
            const msgs = await getMessages({ threadId: this.thread.id, limitSize: 20 });
            this.messages = this._enrichMessages(msgs);
            if (msgs.length > 0) {
                this._lastMsgDate = msgs[msgs.length - 1].createdDate;
            }
            this._scrollToBottom();
        } catch (e) {
            this.errorMsg = this._extractError(e);
        }
    }

    _startPolling() {
        this._stopPolling();
        this._pollTimer = setInterval(() => this._pollNewMessages(), POLL_INTERVAL_MS);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async _pollNewMessages() {
        if (!this.thread || this.thread.isClosed) return;
        try {
            const since = this._lastMsgDate || new Date(0).toISOString();
            const newMsgs = await getMessagesSince({
                threadId: this.thread.id,
                sinceCreatedDate: since
            });
            if (newMsgs && newMsgs.length > 0) {
                this.messages = [...this.messages, ...this._enrichMessages(newMsgs)];
                this._lastMsgDate = newMsgs[newMsgs.length - 1].createdDate;
                this._scrollToBottom();
            }
        } catch (e) {
            // Silently fail polling
        }
    }

    _scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.refs?.msgContainer;
            if (container) container.scrollTop = container.scrollHeight;
        }, 100);
    }

    // ─── Handlers ────────────────────────────────────────────────────────────

    handleReasonChange(e)      { this.reason         = e.detail.value; }
    handleInitialMsgChange(e)  { this.initialMessage = e.detail.value; }
    handleBodyChange(e)        { this.messageBody    = e.detail.value; }
    handleStatusChange(e)      { this.newStatus      = e.detail.value; }

    async handleStartThread() {
        if (!this.reason) {
            this.errorMsg = 'Selecione um motivo.';
            return;
        }
        this.isLoading = true;
        this.errorMsg  = '';
        try {
            const t = await getOrCreateThread({
                recordId:       this.recordId,
                objectApiName:  this.objectApiName,
                reason:         this.reason,
                initialMessage: this.initialMessage
            });
            this.thread    = t;
            this.newStatus = t.status;
            await this._loadMessages();
            this._startPolling();
        } catch (e) {
            this.errorMsg = this._extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleSend() {
        const body = (this.messageBody || '').trim();
        if (!body) return;
        this.isSending = true;
        this.errorMsg  = '';
        try {
            const msg = await postMessage({ threadId: this.thread.id, body });
            this.messages = [...this.messages, ...this._enrichMessages([msg])];
            this._lastMsgDate = msg.createdDate;
            this.messageBody = '';
            this._scrollToBottom();
        } catch (e) {
            this.errorMsg = this._extractError(e);
        } finally {
            this.isSending = false;
        }
    }

    async handleUpdateStatus() {
        if (!this.newStatus) return;
        this.errorMsg = '';
        try {
            const msg = await changeStatus({ threadId: this.thread.id, status: this.newStatus });
            this.thread = { ...this.thread, status: this.newStatus, isClosed: this.newStatus === 'Closed' };
            this.messages = [...this.messages, ...this._enrichMessages([msg])];
            this._lastMsgDate = msg.createdDate;
            if (this.thread.isClosed) this._stopPolling();
            this._scrollToBottom();
        } catch (e) {
            this.errorMsg = this._extractError(e);
        }
    }

    async handleUploadFinished(e) {
        const files = e.detail.files;
        if (!files || files.length === 0) return;
        const contentDocumentId = files[0].documentId;
        this.errorMsg = '';
        try {
            const msg = await linkUploadedFileToThread({
                threadId: this.thread.id,
                contentDocumentId
            });
            this.messages = [...this.messages, ...this._enrichMessages([msg])];
            this._lastMsgDate = msg.createdDate;
            this._scrollToBottom();
        } catch (e) {
            this.errorMsg = this._extractError(e);
        }
    }

    handleFileClick(e) {
        e.preventDefault();
        const docId = e.currentTarget.dataset.docid;
        if (!docId) return;
        // Try NavigationMixin first; fallback URL as href
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: docId }
        });
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    _enrichMessages(msgs) {
        return msgs.map(m => ({
            ...m,
            isUserMessage:  m.messageType === 'UserMessage',
            isStatusChange: m.messageType === 'StatusChange',
            isFile:         m.messageType === 'File',
            formattedDate:  m.createdDate
                ? new Date(m.createdDate).toLocaleString('pt-BR')
                : '',
            cssClass: 'chat-msg'
        }));
    }

    _extractError(e) {
        if (e && e.body && e.body.message) return e.body.message;
        if (e && e.message) return e.message;
        return 'Erro desconhecido.';
    }
}
