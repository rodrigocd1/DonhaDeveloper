import { LightningElement, api, track } from 'lwc';
import sendMessage from '@salesforce/apex/CommunicatorChatController.sendMessage';
import sendMessageWithAttachments from '@salesforce/apex/CommunicatorChatController.sendMessageWithAttachments';
import validateUploadedFiles from '@salesforce/apex/CommunicatorChatController.validateUploadedFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { isSalesforceMobileApp, buildDisabledFeatureToast, SALESFORCE_APP_DISABLED_MESSAGE } from 'c/communicatorEnvironment';

const LARGE_UPLOAD_SUCCESS_MESSAGE = 'Arquivo(s) anexado(s) com sucesso.';
const LARGE_UPLOAD_DUPLICATE_MESSAGE = 'Alguns arquivos ja estavam anexados e foram ignorados.';
const LARGE_UPLOAD_MISSING_ID_MESSAGE = 'Nao foi possivel resolver o ID de alguns arquivos. Verifique suas permissoes e tente novamente.';

export default class CommunicatorChatMessageInput extends LightningElement {
    @api threadId;
    @api uploadRecordId;
    @api compactMode = false;
    _disabled = false;

    @track messageText = '';
    @track isSending = false;
    @track isUploading = false;
    @track showMentionPicker = false;
    @track selectedMentions = []; // { id, name, type, isGroup, chipClass }
    @track uploadedFiles = []; // { localId, name, isPending, contentDocumentId }
    @track uploadError = null;

    _uploadSequence = 0;
    _mentionTriggerIndex = null;

    @api
    get disabled() {
        return this._disabled;
    }

    set disabled(value) {
        this._disabled = value === true || value === 'true';
        if (this._disabled) {
            this.showMentionPicker = false;
        }
    }

    handleInput(event) {
        if (this.isComposerDisabled) return;
        this.messageText = event.target.value;
        this._autoResizeTextarea(event.target);

        const value = event.target.value;
        const lastTypedCharacter = value[event.target.selectionStart - 1];
        if (lastTypedCharacter === '@') {
            this._mentionTriggerIndex = event.target.selectionStart - 1;
            this.showMentionPicker = true;
        }

        this._syncMentionsWithText();
    }

    handleKeyDown(event) {
        if (this.isComposerDisabled) return;
        if (event.key === 'Escape') {
            this.showMentionPicker = false;
            return;
        }
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    handleMentionSelect(event) {
        if (this.isComposerDisabled) return;
        const { id, name, type } = event.detail;
        const isGroup = type === 'Group';

        if (!this.selectedMentions.find(mention => mention.id === id)) {
            this.selectedMentions = [
                ...this.selectedMentions,
                {
                    id,
                    name,
                    type,
                    isGroup,
                    chipClass: isGroup
                        ? 'comm-input__mention-chip comm-input__mention-chip--group'
                        : 'comm-input__mention-chip comm-input__mention-chip--user'
                }
            ];
        }

        this._insertMentionInline(name);
        this.showMentionPicker = false;
    }

    handleMentionClose() {
        this.showMentionPicker = false;
    }

    handleRemoveMention(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedMentions = this.selectedMentions.filter(mention => mention.id !== id);
    }

    async handleLargeUploadFinished(event) {
        if (this.isUploadDisabled) return;
        const uploadedFiles = Array.isArray(event?.detail?.files) ? event.detail.files : [];
        if (!uploadedFiles.length) return;

        const existingIds = new Set(
            this.uploadedFiles
                .filter(file => !!file.contentDocumentId)
                .map(file => file.contentDocumentId)
        );

        const candidateMap = new Map();
        let missingIdCount = 0;
        let duplicateCount = 0;

        for (const uploaded of uploadedFiles) {
            const contentDocumentId = this._normalizeDocumentId(uploaded?.documentId);
            const fileName = String(uploaded?.name || '').trim() || 'arquivo';

            if (!contentDocumentId) {
                missingIdCount += 1;
                continue;
            }
            if (existingIds.has(contentDocumentId)) {
                duplicateCount += 1;
                continue;
            }

            candidateMap.set(contentDocumentId, fileName);
        }

        if (candidateMap.size > 0) {
            try {
                const validation = await validateUploadedFiles({
                    contentDocumentIds: Array.from(candidateMap.keys())
                });

                const newUploads = [];
                for (const docId of (validation.validContentDocumentIds || [])) {
                    const fileName = candidateMap.get(docId) || 'arquivo';
                    if (!existingIds.has(docId)) {
                        existingIds.add(docId);
                        newUploads.push(this._createCompletedUpload(fileName, docId));
                    }
                }

                if (newUploads.length > 0) {
                    this.uploadedFiles = [...this.uploadedFiles, ...newUploads];
                    this.uploadError = null;
                    this._showToast('Sucesso', LARGE_UPLOAD_SUCCESS_MESSAGE, 'success');
                }

                const rejectedNames = validation.rejectedFileNames || [];
                if (rejectedNames.length > 0) {
                    const errorMsg = validation.errorMessage || 'O arquivo selecionado ultrapassa o tamanho máximo permitido para envio.';
                    this.uploadError = errorMsg;
                    this._showToast('Arquivo não permitido', errorMsg, 'error');
                }
            } catch (error) {
                const message = error?.body?.message || error?.message || 'Erro ao validar arquivo(s).';
                this.uploadError = message;
                this._showToast('Erro', message, 'error');
            }
        }

        if (duplicateCount > 0) {
            this._showToast('Aviso', LARGE_UPLOAD_DUPLICATE_MESSAGE, 'warning');
        }
        if (missingIdCount > 0) {
            this._showToast('Erro', LARGE_UPLOAD_MISSING_ID_MESSAGE, 'error');
        }
    }

    handleRemoveAttachment(event) {
        if (this.isUploadDisabled) return;
        const uploadKey = event?.currentTarget?.dataset?.uploadKey;
        if (!uploadKey) return;

        const targetUpload = this.uploadedFiles.find(file => file.localId === uploadKey);
        if (!targetUpload || targetUpload.isPending) return;

        this._removeUpload(uploadKey);
        this.uploadError = null;
    }

    async handleSend() {
        if (this.isSendDisabled) return;

        const hasText = this.messageText?.trim().length > 0;
        const hasFile = this._hasUploadedAttachments();
        if (!hasText && !hasFile) return;

        const mentionIds = this.selectedMentions.map(mention => mention.id).join(';');

        this.isSending = true;
        try {
            if (hasFile) {
                await this._sendMessageWithUploadedAttachments(mentionIds || null);
            } else {
                await sendMessage({
                    threadId: this.threadId,
                    messageBody: this.messageText,
                    mentionIds: mentionIds || null
                });
            }
            this._reset();
            this.dispatchEvent(new CustomEvent('messagesent'));
        } catch (error) {
            const message = error.body?.message || error.message || 'Falha ao enviar mensagem.';
            this._showToast('Erro', message, 'error');
        } finally {
            this.isSending = false;
        }
    }

    _createCompletedUpload(fileName, contentDocumentId) {
        return {
            localId: `upload-${++this._uploadSequence}`,
            name: fileName,
            isPending: false,
            contentDocumentId
        };
    }

    _normalizeDocumentId(documentId) {
        const value = String(documentId || '').trim();
        return value ? value : null;
    }

    _removeUpload(localId) {
        this.uploadedFiles = this.uploadedFiles.filter(file => file.localId !== localId);
    }

    _hasUploadedAttachments() {
        return this.uploadedFiles.some(file => !file.isPending && !!file.contentDocumentId);
    }

    _getUploadedAttachments() {
        return this.uploadedFiles.filter(file => !file.isPending && !!file.contentDocumentId);
    }

    async _sendMessageWithUploadedAttachments(mentionIds) {
        const uploadedAttachments = this._getUploadedAttachments();
        const contentDocumentIds = uploadedAttachments
            .map(attachment => attachment.contentDocumentId)
            .filter(contentDocumentId => !!contentDocumentId);

        if (!contentDocumentIds.length) return;

        await sendMessageWithAttachments({
            threadId: this.threadId,
            messageBody: this.messageText,
            contentDocumentIds,
            mentionIds
        });
    }

    _reset() {
        this.messageText = '';
        this.selectedMentions = [];
        this.uploadedFiles = [];
        this.uploadError = null;
        this._uploadSequence = 0;
        this.showMentionPicker = false;
        this._mentionTriggerIndex = null;

        const textareaElement = this.template.querySelector('.comm-input__textarea');
        if (textareaElement) {
            textareaElement.value = '';
            textareaElement.style.height = 'auto';
            this._autoResizeTextarea(textareaElement);
        }
    }

    _insertMentionInline(name) {
        const textareaElement = this.template.querySelector('.comm-input__textarea');
        const currentText = this.messageText || '';
        const mentionToken = `@${name}`;
        const caret = textareaElement?.selectionStart ?? currentText.length;

        const mentionStartIndex = this._resolveMentionStartIndex(currentText, caret);
        const insertionResult = this._buildMentionInsertion(
            currentText,
            mentionToken,
            mentionStartIndex
        );

        this.messageText = insertionResult.nextText;
        this._mentionTriggerIndex = null;
        this._applyMentionTextToTextarea(
            textareaElement,
            insertionResult.nextText,
            insertionResult.nextCaret
        );
        this._syncMentionsWithText();
    }

    _resolveMentionStartIndex(currentText, caret) {
        const mentionStartIndex = this._mentionTriggerIndex;
        const isValidTrigger =
            mentionStartIndex != null &&
            mentionStartIndex >= 0 &&
            mentionStartIndex < currentText.length &&
            currentText.charAt(mentionStartIndex) === '@';

        if (isValidTrigger) return mentionStartIndex;
        return currentText.lastIndexOf('@', Math.max(0, caret - 1));
    }

    _buildMentionInsertion(currentText, mentionToken, mentionStartIndex) {
        if (mentionStartIndex >= 0 && currentText.charAt(mentionStartIndex) === '@') {
            const textBeforeMention = currentText.slice(0, mentionStartIndex);
            const textAfterMention = currentText.slice(mentionStartIndex + 1);
            const requiresSpacer = textAfterMention.length > 0 && !/^\s/.test(textAfterMention);
            const spacer = requiresSpacer ? ' ' : '';
            return {
                nextText: `${textBeforeMention}${mentionToken}${spacer}${textAfterMention}`,
                nextCaret: (textBeforeMention + mentionToken + spacer).length
            };
        }

        const prefix = currentText && !/\s$/.test(currentText) ? ' ' : '';
        const nextText = `${currentText}${prefix}${mentionToken} `;
        return { nextText, nextCaret: nextText.length };
    }

    _applyMentionTextToTextarea(textareaElement, text, caret) {
        if (!textareaElement) return;
        textareaElement.value = text;
        textareaElement.focus();
        textareaElement.selectionStart = caret;
        textareaElement.selectionEnd = caret;
        this._autoResizeTextarea(textareaElement);
    }

    _syncMentionsWithText() {
        if (!this.selectedMentions?.length) return;
        const text = this.messageText || '';
        this.selectedMentions = this.selectedMentions.filter(mention =>
            text.includes(`@${mention.name}`)
        );
    }

    _autoResizeTextarea(element) {
        if (!element) return;
        if (this.isCompactIos) {
            this._resizeCompactIosTextarea(element);
            return;
        }

        const maxHeight = 160;
        element.style.height = 'auto';
        element.style.height = `${Math.min(element.scrollHeight, maxHeight)}px`;
    }

    _resizeCompactIosTextarea(element) {
        element.style.height = 'auto';
        const styles = window.getComputedStyle(element);
        const lineHeight = parseFloat(styles.lineHeight) || 16;
        const paddingTop = parseFloat(styles.paddingTop) || 0;
        const paddingBottom = parseFloat(styles.paddingBottom) || 0;
        const borderTop = parseFloat(styles.borderTopWidth) || 0;
        const borderBottom = parseFloat(styles.borderBottomWidth) || 0;
        const frameSize = paddingTop + paddingBottom + borderTop + borderBottom;
        const minLines = 1;
        const maxLines = this._getCompactIosMaxLines();
        const minHeight = lineHeight * minLines + frameSize;
        const maxHeight = lineHeight * maxLines + frameSize;
        const nextHeight = Math.min(Math.max(element.scrollHeight, minHeight), maxHeight);
        element.style.height = `${nextHeight}px`;
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get isSendDisabled() {
        const hasText = this.messageText?.trim().length > 0;
        const hasFile = this._hasUploadedAttachments();
        return this.isComposerDisabled || this.isBusy || (!hasText && !hasFile);
    }

    get showMentionPickerState() {
        return this.showMentionPicker && !this.isComposerDisabled;
    }

    get isComposerDisabled() {
        return this._disabled === true;
    }

    get isInputDisabled() {
        return this.isSending || this.isComposerDisabled;
    }

    get isEnvironmentUploadDisabled() {
        return isSalesforceMobileApp();
    }

    get uploadVisualClass() {
        return this.isEnvironmentUploadDisabled
            ? 'comm-input__upload-visual comm-input__upload-visual--env-disabled'
            : 'comm-input__upload-visual';
    }

    get environmentDisabledTitle() {
        return SALESFORCE_APP_DISABLED_MESSAGE;
    }

    handleEnvironmentDisabledClick() {
        this.dispatchEvent(buildDisabledFeatureToast());
    }

    get isUploadDisabled() {
        return this.isBusy || this.isComposerDisabled;
    }

    get hasMentions() {
        return this.selectedMentions && this.selectedMentions.length > 0;
    }

    get hasUploadedFiles() {
        return this.uploadedFiles.length > 0;
    }

    get acceptedFormats() {
        return '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.png,.jpg,.jpeg,.gif,.zip,.txt,.csv';
    }

    get acceptedFormatsList() {
        return this.acceptedFormats
            .split(',')
            .map(format => format.trim())
            .filter(format => !!format);
    }

    get largeUploadRecordId() {
        return this.uploadRecordId || this.threadId || null;
    }

    get isBusy() {
        return this.isSending || this.isUploading;
    }

    get inputClass() {
        return this.isCompactIos ? 'comm-input comm-input--ios-compact' : 'comm-input';
    }

    get textareaRows() {
        return this.isCompactIos ? 1 : 4;
    }

    get isCompactIos() {
        if (!this.compactMode) return false;
        if (!this._isIosDevice()) return false;
        if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return false;
        return window.matchMedia('(max-width: 767px)').matches;
    }

    _isIosDevice() {
        const userAgent = navigator.userAgent || '';
        const platform = navigator.platform || '';
        const maxTouchPoints = navigator.maxTouchPoints || 0;
        return /iPad|iPhone|iPod/.test(userAgent) || (platform === 'MacIntel' && maxTouchPoints > 1);
    }

    _getCompactIosMaxLines() {
        const viewportWidth = Number(window.innerWidth || 0);
        const viewportHeight = Number(window.innerHeight || 0);

        if (viewportWidth <= 390 && viewportHeight <= 850) {
            return 1;
        }

        if (viewportWidth <= 414 && viewportHeight <= 900) {
            return 2;
        }

        return 3;
    }
}