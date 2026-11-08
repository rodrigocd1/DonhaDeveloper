import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord } from 'lightning/uiRecordApi';
import validateBroadcastUploadedFiles from '@salesforce/apex/CommunicatorChatController.validateBroadcastUploadedFiles';
import uploadBroadcastTemporaryAttachmentFromBase64 from '@salesforce/apex/CommunicatorChatController.uploadBroadcastTemporaryAttachmentFromBase64';
import publishBroadcastMessage from '@salesforce/apex/CommunicatorChatController.publishBroadcastMessage';
import editBroadcastMessage from '@salesforce/apex/CommunicatorChatController.editBroadcastMessage';

const MODE_PUBLISH = 'publish';
const MODE_EDIT = 'edit';
const MESSAGE_STATUS_QUEUED = 'Queued';
const ACCEPTED_FORMATS = '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.png,.jpg,.jpeg,.gif,.zip,.txt,.csv';
const SUBJECT_MAX_LENGTH = 255;
const CLIPBOARD_IMAGE_TYPES = new Set(['image/png', 'image/jpeg']);
const CLIPBOARD_EXTENSION_BY_TYPE = {
    'image/png': 'png',
    'image/jpeg': 'jpg'
};

export default class CommunicatorBroadcastComposer extends LightningElement {
    _broadcast = null;
    _mode = MODE_PUBLISH;
    _editingMessage = null;
    _editingAttachmentDraft = null;
    _lastBroadcastId = null;
    _lastEditingMessageId = null;
    _fileSequence = 0;
    _clipboardFileSequence = 0;
    _uploadInputVersion = 0;

    @track messageBody = '';
    @track messageSubject = '';
    @track uploadedFiles = [];
    @track uploadErrorMessage = '';
    @track isSubmitting = false;
    @track isAttachmentProcessing = false;

    @api uploadConfigValid = false;
    @api uploadConfigErrorMessage = '';
    @api maxUploadBroadcastFileSizeMB = null;
    @api maxClipboardBroadcastImageSizeMB = null;

    @api
    get broadcast() {
        return this._broadcast;
    }

    set broadcast(value) {
        const nextBroadcast = value || null;
        const nextBroadcastId = nextBroadcast?.groupId || null;
        const changed = nextBroadcastId !== this._lastBroadcastId;
        this._broadcast = nextBroadcast;
        this._lastBroadcastId = nextBroadcastId;
        if (changed && !this.isEditMode) {
            this._resetPublishState();
        }
    }

    @api
    get mode() {
        return this._mode;
    }

    set mode(value) {
        const nextMode = value === MODE_EDIT ? MODE_EDIT : MODE_PUBLISH;
        const changed = nextMode !== this._mode;
        this._mode = nextMode;
        if (changed || this.isEditMode) {
            this._syncFromInputs();
        } else if (!this.isEditMode) {
            this._resetPublishState();
        }
    }

    @api
    get editingMessage() {
        return this._editingMessage;
    }

    set editingMessage(value) {
        const nextMessage = value || null;
        const nextMessageId = nextMessage?.Id || null;
        const changed = nextMessageId !== this._lastEditingMessageId;
        this._editingMessage = nextMessage;
        this._lastEditingMessageId = nextMessageId;
        if (this.isEditMode && changed) {
            this._syncFromInputs();
        }
    }

    @api
    get editingAttachmentDraft() {
        return this._editingAttachmentDraft;
    }

    set editingAttachmentDraft(value) {
        this._editingAttachmentDraft = value || null;
    }

    connectedCallback() {
        this._syncFromInputs();
    }

    renderedCallback() {
        this._syncTextareaValue();
    }

    get isEditMode() {
        return this._mode === MODE_EDIT;
    }

    get isPublishMode() {
        return !this.isEditMode;
    }

    get hasBroadcast() {
        return !!this.broadcast?.groupId;
    }

    get acceptedFormatsList() {
        return ACCEPTED_FORMATS
            .split(',')
            .map(format => format.trim())
            .filter(format => !!format);
    }

    get messagePlaceholder() {
        return this.isEditMode ? 'Edite a mensagem...' : 'Digite a sua publicação...';
    }

    get subjectPlaceholder() {
        return this.isEditMode ? 'Edite o assunto do comunicado' : 'Informe o assunto do comunicado';
    }

    get hasAttachments() {
        return this.displayedFiles.length > 0;
    }

    get displayedFiles() {
        return this.isEditMode
            ? (this._editingAttachmentDraft?.visibleAttachments || [])
            : (this.uploadedFiles || []);
    }

    get uploadInputTokens() {
        return [this._uploadInputVersion];
    }

    get uploadClass() {
        return this.isUploadDisabled
            ? 'comm-broadcast-composer__upload comm-broadcast-composer__upload--disabled'
            : 'comm-broadcast-composer__upload';
    }

    get isUploadDisabled() {
        return this.isSubmitting || this.isAttachmentProcessing || !this.hasBroadcast || !this.uploadConfigValid;
    }

    get submitLabel() {
        return this.isEditMode ? 'Salvar edição' : 'Publicar comunicado';
    }

    get isSubmitDisabled() {
        const hasSubject = this.messageSubject.trim().length > 0;
        const isSubjectTooLong = this.messageSubject.trim().length > SUBJECT_MAX_LENGTH;
        const hasText = this.messageBody.trim().length > 0;
        const hasFiles = this.hasAttachments;
        if (this.isEditMode) {
            return this.isSubmitting
                || this.isAttachmentProcessing
                || !this._isEditingMessageReady()
                || !hasSubject
                || isSubjectTooLong
                || !hasText;
        }
        return this.isSubmitting
            || this.isAttachmentProcessing
            || !this.hasBroadcast
            || !hasSubject
            || isSubjectTooLong
            || (!hasText && !hasFiles);
    }

    get subjectCharacterCount() {
        return this.messageSubject.trim().length;
    }

    get isSubjectTooLong() {
        return this.subjectCharacterCount > SUBJECT_MAX_LENGTH;
    }

    get subjectErrorMessage() {
        if (this.isSubjectTooLong) {
            return `O assunto do comunicado excede o limite permitido de ${SUBJECT_MAX_LENGTH} caracteres.`;
        }
        return '';
    }

    handleMessageInput(event) {
        this.messageBody = String(event.target.value || '');
        this.uploadErrorMessage = '';
    }

    handleSubjectInput(event) {
        this.messageSubject = String(event.target.value || '');
        this.uploadErrorMessage = '';
    }

    handleKeyDown(event) {
        if (event.key !== 'Enter' || event.shiftKey) {
            return;
        }

        event.preventDefault();
        if (!this.isSubmitDisabled) {
            this.handleSubmit();
        }
    }

    async handleBodyPaste(event) {
        const clipboardFiles = this._extractClipboardImageFiles(event);
        if (!clipboardFiles.length) return;

        if (this.isSubmitting || !this.hasBroadcast || !this.uploadConfigValid) {
            const message = this.uploadConfigErrorMessage || 'Não foi possível validar imagens coladas neste momento.';
            this.uploadErrorMessage = message;
            this._showToast('Erro', message, 'error');
            return;
        }

        await this._uploadClipboardImages(clipboardFiles);
    }

    async handleUploadFinished(event) {
        if (!this.hasBroadcast || !this.uploadConfigValid) {
            return;
        }

        const files = Array.isArray(event?.detail?.files) ? event.detail.files : [];
        if (!files.length) return;

        this.isAttachmentProcessing = true;
        try {
            const nextFiles = this.isEditMode
                ? [...(this._editingAttachmentDraft?.visibleAttachments || [])]
                : [...this.uploadedFiles];
            const existingIds = new Set(nextFiles.map(file => file.documentId));
            const candidateMap = new Map();
            let missingIdCount = 0;
            let duplicateCount = 0;

            files.forEach(file => {
                const documentId = this._normalizeDocumentId(file?.documentId);
                const fileName = String(file?.name || '').trim() || 'arquivo';
                if (!documentId) {
                    missingIdCount += 1;
                    return;
                }
                if (existingIds.has(documentId)) {
                    duplicateCount += 1;
                    return;
                }

                candidateMap.set(documentId, fileName);
            });

            if (candidateMap.size > 0) {
                const validation = await validateBroadcastUploadedFiles({
                    broadcastGroupId: this.broadcast.groupId,
                    contentDocumentIds: Array.from(candidateMap.keys())
                });

                const validDocumentIds = Array.isArray(validation?.validContentDocumentIds)
                    ? validation.validContentDocumentIds
                        .map(documentId => this._normalizeDocumentId(documentId))
                        .filter(documentId => !!documentId)
                    : [];
                const rejectedFileNames = Array.isArray(validation?.rejectedFileNames)
                    ? validation.rejectedFileNames
                    : [];
                const newUploads = [];

                validDocumentIds.forEach(documentId => {
                    if (existingIds.has(documentId)) {
                        return;
                    }
                    const fileName = candidateMap.get(documentId) || 'arquivo';
                    existingIds.add(documentId);
                    newUploads.push({
                        localId: `broadcast-upload-${++this._fileSequence}`,
                        documentId,
                        fileName,
                        origin: 'new'
                    });
                });

                if (newUploads.length > 0) {
                    if (this.isEditMode) {
                        this.dispatchEvent(new CustomEvent('editattachmentsadded', {
                            detail: { files: newUploads }
                        }));
                    } else {
                        this.uploadedFiles = [...nextFiles, ...newUploads];
                    }
                    this.uploadErrorMessage = '';
                    this._showToast('Sucesso', 'Anexo(s) adicionado(s) ao comunicado.', 'success');
                }

                if (rejectedFileNames.length > 0) {
                    const errorMessage =
                        validation?.errorMessage ||
                        'O arquivo selecionado ultrapassa o tamanho maximo permitido para envio.';
                    this.uploadErrorMessage = errorMessage;
                    this._showToast('Arquivo nao permitido', errorMessage, 'error');
                }
            }

            if (missingIdCount > 0) {
                this._showToast('Erro', 'Não foi possível validar um ou mais arquivos selecionados.', 'error');
            }

            if (duplicateCount > 0) {
                this._showToast('Aviso', 'Alguns arquivos ja estavam adicionados ao comunicado.', 'warning');
            }
        } catch (error) {
            const message = this._normalizeError(error) || 'Erro ao validar arquivo(s).';
            this.uploadErrorMessage = message;
            this._showToast('Erro', message, 'error');
        } finally {
            this.isAttachmentProcessing = false;
            this._refreshUploadInput();
        }
    }

    async handleRemoveAttachment(event) {
        const localId = String(event.currentTarget?.dataset?.uploadId || '').trim();
        if (!localId) return;

        const targetFile = (this.uploadedFiles || []).find(file => file.localId === localId);
        const displayedTargetFile = (this.displayedFiles || []).find(file => file.localId === localId);
        if (this.isEditMode) {
            if (!displayedTargetFile) return;
            this.dispatchEvent(new CustomEvent('editattachmentremove', {
                detail: {
                    documentId: displayedTargetFile.documentId,
                    origin: displayedTargetFile.origin || 'new'
                }
            }));
            return;
        }
        if (!targetFile) {
            return;
        }

        this.isAttachmentProcessing = true;
        try {
            if (targetFile.documentId) {
                await deleteRecord(targetFile.documentId);
            }

            this.uploadedFiles = this.uploadedFiles.filter(file => file.localId !== localId);
            this.uploadErrorMessage = '';
        } catch (error) {
            const message = this._normalizeError(error) || 'Não foi possível remover o anexo.';
            this.uploadErrorMessage = message;
            this._showToast('Erro', message, 'error');
        } finally {
            this.isAttachmentProcessing = false;
            this._refreshUploadInput();
        }
    }

    handleCancel() {
        if (this.isEditMode) {
            this.dispatchEvent(new CustomEvent('canceledit'));
            return;
        }
        this._resetPublishState();
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) return;

        const messageSubject = this.messageSubject.trim();
        const messageBody = this.messageBody.trim();
        if (!messageSubject) {
            this.uploadErrorMessage = 'Informe o assunto do comunicado.';
            return;
        }
        if (messageSubject.length > SUBJECT_MAX_LENGTH) {
            this.uploadErrorMessage = this.subjectErrorMessage;
            return;
        }
        this.isSubmitting = true;
        try {
            if (this.isEditMode) {
                const editedMessage = await editBroadcastMessage({
                    messageId: this.editingMessage.Id,
                    messageSubject,
                    messageBody,
                    newContentDocumentIds: this._getEditNewContentDocumentIds(),
                    removedContentDocumentIds: this._getEditRemovedContentDocumentIds()
                });
                this._showToast('Sucesso', 'Mensagem atualizada com sucesso.', 'success');
                this.dispatchEvent(new CustomEvent('saveedit', {
                    detail: {
                        message: editedMessage || null,
                        messageId: editedMessage?.Id || this.editingMessage.Id,
                        groupId: this.broadcast?.groupId || null,
                        removedContentDocumentIds: this._getEditRemovedContentDocumentIds()
                    }
                }));
                return;
            }

            const validatedDocumentIds = await this._validateBroadcastFiles();
            const publishedMessage = await publishBroadcastMessage({
                broadcastGroupId: this.broadcast.groupId,
                messageSubject,
                messageBody,
                contentDocumentIds: validatedDocumentIds
            });

            const successMessage = publishedMessage?.status === MESSAGE_STATUS_QUEUED
                ? 'Publicação enfileirada. A distribuição está em processamento.'
                : 'Publicação enviada com sucesso.';
            this._showToast('Sucesso', successMessage, 'success');
            this.dispatchEvent(new CustomEvent('published', {
                detail: {
                    groupId: this.broadcast.groupId,
                    message: publishedMessage || null,
                    messageId: publishedMessage?.Id || null
                }
            }));
            this._resetPublishState();
        } catch (error) {
            const message = this._normalizeError(error) || 'Não foi possível concluir a operação.';
            this.uploadErrorMessage = message;
            this._showToast('Erro', message, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    _syncFromInputs() {
        if (this.isEditMode) {
            this.messageSubject = String(this.editingMessage?.subject || '');
            this.messageBody = String(this.editingMessage?.body || '');
            this.uploadedFiles = [];
            this.uploadErrorMessage = '';
            this._syncTextareaValue();
            return;
        }

        this._resetPublishState();
    }

    _resetPublishState() {
        this.messageSubject = '';
        this.messageBody = '';
        this.uploadedFiles = [];
        this.uploadErrorMessage = '';
        this.isAttachmentProcessing = false;
        this._fileSequence = 0;
        this._clipboardFileSequence = 0;
        this._refreshUploadInput();
        this._clearTextareaValue();
    }

    _isEditingMessageReady() {
        return !!this.editingMessage?.Id;
    }

    _getEditNewContentDocumentIds() {
        return (this._editingAttachmentDraft?.newAttachments || [])
            .map(file => this._normalizeDocumentId(file?.documentId))
            .filter(documentId => !!documentId);
    }

    _getEditRemovedContentDocumentIds() {
        return (this._editingAttachmentDraft?.removedOriginalAttachmentIds || [])
            .map(documentId => this._normalizeDocumentId(documentId))
            .filter(documentId => !!documentId);
    }

    async _validateBroadcastFiles() {
        const selectedDocumentIds = this.uploadedFiles
            .map(file => file.documentId)
            .filter(documentId => !!documentId);

        if (!selectedDocumentIds.length) {
            return [];
        }

        const validation = await validateBroadcastUploadedFiles({
            broadcastGroupId: this.broadcast.groupId,
            contentDocumentIds: selectedDocumentIds
        });
        const validDocumentIds = Array.isArray(validation?.validContentDocumentIds)
            ? validation.validContentDocumentIds
                .map(documentId => this._normalizeDocumentId(documentId))
                .filter(documentId => !!documentId)
            : [];
        const rejectedFileNames = Array.isArray(validation?.rejectedFileNames)
            ? validation.rejectedFileNames
            : [];
        if (rejectedFileNames.length > 0) {
            const errorMessage = validation?.errorMessage || 'Alguns anexos excedem o limite permitido.';
            const validDocumentIdSet = new Set(validDocumentIds);

            this.uploadedFiles = this.uploadedFiles.filter(file => validDocumentIdSet.has(file.documentId));
            this.uploadErrorMessage = errorMessage;
            this._refreshUploadInput();

            if (!validDocumentIds.length) {
                throw new Error(errorMessage);
            }

            this._showToast('Arquivo nao permitido', errorMessage, 'error');
            return validDocumentIds;
        }

        return validDocumentIds.length > 0 ? validDocumentIds : selectedDocumentIds;
    }

    _extractClipboardImageFiles(event) {
        const clipboardData = event?.clipboardData;
        const candidateMap = new Map();
        const addFile = file => {
            if (!file || !CLIPBOARD_IMAGE_TYPES.has(String(file.type || '').toLowerCase())) return;
            const key = `${String(file.name || '').trim()}|${file.type}|${file.size}`;
            if (!candidateMap.has(key)) {
                candidateMap.set(key, file);
            }
        };

        Array.from(clipboardData?.items || []).forEach(item => {
            if (item?.kind !== 'file') return;
            const type = String(item.type || '').toLowerCase();
            if (!CLIPBOARD_IMAGE_TYPES.has(type)) return;
            try {
                addFile(item.getAsFile());
            } catch (error) {
                // Ignore unavailable clipboard files and preserve normal paste behavior.
            }
        });

        Array.from(clipboardData?.files || []).forEach(file => addFile(file));
        return Array.from(candidateMap.values());
    }

    async _uploadClipboardImages(files) {
        const maxBytes = this._getClipboardImageMaxBytes();
        if (!maxBytes) {
            const message = 'Não foi possível validar o limite de imagens coladas.';
            this.uploadErrorMessage = message;
            this._showToast('Erro', message, 'error');
            return;
        }

        this.isAttachmentProcessing = true;
        const newUploads = [];
        const existingIds = new Set(
            (this.displayedFiles || [])
                .map(file => this._normalizeDocumentId(file?.documentId))
                .filter(documentId => !!documentId)
        );

        try {
            for (const file of files) {
                const preparedFile = this._prepareClipboardImageFile(file);
                if (!preparedFile) continue;

                if (preparedFile.file.size > maxBytes) {
                    const message = this._getClipboardImageSizeErrorMessage();
                    this.uploadErrorMessage = message;
                    this._showToast('Imagem muito grande', message, 'error');
                    continue;
                }

                try {
                    const base64Data = await this._readFileAsBase64(preparedFile.file);
                    const uploadedFile = await uploadBroadcastTemporaryAttachmentFromBase64({
                        broadcastGroupId: this.broadcast.groupId,
                        fileName: preparedFile.fileName,
                        base64Data,
                        contentType: preparedFile.contentType
                    });
                    const documentId = this._normalizeDocumentId(uploadedFile?.contentDocumentId);
                    if (!documentId || existingIds.has(documentId)) continue;

                    existingIds.add(documentId);
                    newUploads.push({
                        localId: `broadcast-upload-${++this._fileSequence}`,
                        documentId,
                        fileName: String(uploadedFile?.fileName || preparedFile.fileName),
                        origin: 'new'
                    });
                } catch (error) {
                    const message = this._normalizeError(error) || 'Não foi possível anexar a imagem colada.';
                    this.uploadErrorMessage = message;
                    this._showToast('Erro', message, 'error');
                }
            }

            if (newUploads.length > 0) {
                if (this.isEditMode) {
                    this.dispatchEvent(new CustomEvent('editattachmentsadded', {
                        detail: { files: newUploads }
                    }));
                } else {
                    this.uploadedFiles = [...this.uploadedFiles, ...newUploads];
                }
                this.uploadErrorMessage = '';
                this._showToast('Sucesso', 'Imagem(ns) adicionada(s) ao comunicado.', 'success');
            }
        } finally {
            this.isAttachmentProcessing = false;
            this._refreshUploadInput();
        }
    }

    _prepareClipboardImageFile(file) {
        const contentType = String(file?.type || '').toLowerCase();
        if (!CLIPBOARD_IMAGE_TYPES.has(contentType)) return null;

        const extension = CLIPBOARD_EXTENSION_BY_TYPE[contentType];
        let fileName = String(file?.name || '').trim();
        fileName = fileName.split(/[\\/]/).pop();
        fileName = fileName.replace(/[<>:"/\\|?*\x00-\x1f]+/g, '_').trim();
        if (!fileName) {
            fileName = `imagem-colada-${++this._clipboardFileSequence}.${extension}`;
        } else if (!/\.(png|jpe?g)$/i.test(fileName)) {
            fileName = `${fileName}.${extension}`;
        }

        return { file, fileName, contentType };
    }

    _readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                let dataUrl = String(reader.result || '');
                const separatorIndex = dataUrl.indexOf(',');
                const base64Data = separatorIndex >= 0 ? dataUrl.substring(separatorIndex + 1) : dataUrl;
                dataUrl = '';
                resolve(base64Data);
            };
            reader.onerror = () => reject(new Error('Não foi possível ler a imagem colada.'));
            reader.readAsDataURL(file);
        });
    }

    _getClipboardImageMaxBytes() {
        const limitMB = Number(this.maxClipboardBroadcastImageSizeMB);
        if (!Number.isFinite(limitMB) || limitMB <= 0) return null;
        return limitMB * 1024 * 1024;
    }

    _getClipboardImageSizeErrorMessage() {
        const clipboardLimit = this._formatMegabytes(this.maxClipboardBroadcastImageSizeMB);
        const uploadLimit = this._formatMegabytes(this.maxUploadBroadcastFileSizeMB);
        if (clipboardLimit && uploadLimit) {
            return `Imagens coladas podem ter até ${clipboardLimit} MB. Para arquivos maiores, use Anexar arquivo, com limite de ${uploadLimit} MB.`;
        }
        return 'Imagens coladas ultrapassam o limite permitido. Para arquivos maiores, use Anexar arquivo.';
    }

    _formatMegabytes(value) {
        const numericValue = Number(value);
        if (!Number.isFinite(numericValue) || numericValue <= 0) return null;
        return numericValue.toLocaleString('pt-BR', {
            minimumFractionDigits: Number.isInteger(numericValue) ? 0 : 1,
            maximumFractionDigits: 1
        });
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _refreshUploadInput() {
        this._uploadInputVersion += 1;
    }

    _normalizeDocumentId(documentId) {
        const value = String(documentId || '').trim();
        return value ? value : null;
    }

    _normalizeError(error) {
        return String(
            error?.body?.message
            || error?.message
            || error?.statusText
            || ''
        ).trim();
    }

    _clearTextareaValue() {
        const textareaElement = this.template.querySelector('.comm-broadcast-composer__textarea');
        if (!textareaElement) {
            return;
        }
        textareaElement.value = '';
    }

    _syncTextareaValue() {
        const textareaElement = this.template.querySelector('.comm-broadcast-composer__textarea');
        if (!textareaElement) {
            return;
        }
        const nextValue = String(this.messageBody || '');
        if (textareaElement.value !== nextValue) {
            textareaElement.value = nextValue;
        }
    }
}