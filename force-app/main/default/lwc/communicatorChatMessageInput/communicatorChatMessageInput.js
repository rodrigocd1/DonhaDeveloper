import { LightningElement, api, track } from 'lwc';
import sendMessage                       from '@salesforce/apex/CommunicatorChatController.sendMessage';
import sendMessageWithAttachment         from '@salesforce/apex/CommunicatorChatController.sendMessageWithAttachment';
import { ShowToastEvent }                from 'lightning/platformShowToastEvent';

export default class CommunicatorChatMessageInput extends LightningElement {

    @api threadId;

    @track messageText   = '';
    @track isSending     = false;

    // Armazena o ContentDocumentId retornado pelo lightning-file-upload
    _uploadedContentDocumentId = null;
    _uploadedFileName          = null;

    // ─────────────────────────────────────────
    // Handlers — texto
    // ─────────────────────────────────────────

    handleInput(event) {
        this.messageText = event.target.value;
        this._autoResizeTextarea(event.target);
    }

    handleKeyDown(event) {
        // Enter sem Shift envia; Shift+Enter quebra linha
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    // ─────────────────────────────────────────
    // Handlers — upload
    // ─────────────────────────────────────────

    /**
     * Chamado automaticamente pelo lightning-file-upload após o upload
     * ser concluído com sucesso no servidor.
     * event.detail.files contém: [ { contentVersionId, documentId, name, size } ]
     */
    handleUploadFinished(event) {
        const files = event.detail.files;
        if (!files || files.length === 0) return;

        const uploaded = files[0];
        this._uploadedContentDocumentId = uploaded.documentId;
        this._uploadedFileName          = uploaded.name;

        // Força re-render do preview
        this.uploadedFile = { name: uploaded.name };
    }

    handleRemoveAttachment() {
        this._uploadedContentDocumentId = null;
        this._uploadedFileName          = null;
        this.uploadedFile               = null;
    }

    // ─────────────────────────────────────────
    // Envio
    // ─────────────────────────────────────────

    async handleSend() {
        if (this.isSendDisabled) return;

        this.isSending = true;
        try {
            if (this._uploadedContentDocumentId) {
                await sendMessageWithAttachment({
                    threadId:          this.threadId,
                    messageBody:       this.messageText,
                    contentDocumentId: this._uploadedContentDocumentId
                });
            } else {
                await sendMessage({
                    threadId:    this.threadId,
                    messageBody: this.messageText
                });
            }

            this._reset();
            this.dispatchEvent(new CustomEvent('messagesent'));

        } catch (err) {
            const msg = err.body?.message || err.message || 'Failed to send message.';
            this._showToast('Error', msg, 'error');
        } finally {
            this.isSending = false;
        }
    }

    // ─────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────

    _reset() {
        this.messageText                 = '';
        this._uploadedContentDocumentId  = null;
        this._uploadedFileName           = null;
        this.uploadedFile                = null;

        const textarea = this.template.querySelector('.comm-input__textarea');
        if (textarea) {
            textarea.value       = '';
            textarea.style.height = 'auto';
        }
    }

    _autoResizeTextarea(el) {
        el.style.height = 'auto';
        el.style.height = Math.min(el.scrollHeight, 120) + 'px';
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get isSendDisabled() {
        const hasText = this.messageText?.trim().length > 0;
        const hasFile = !!this._uploadedContentDocumentId;
        return this.isSending || (!hasText && !hasFile);
    }

    get acceptedFormats() {
        return ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
                '.png', '.jpg', '.jpeg', '.gif', '.zip', '.txt', '.csv'];
    }

    // Propriedade reativa para o preview
    @track uploadedFile = null;
}
