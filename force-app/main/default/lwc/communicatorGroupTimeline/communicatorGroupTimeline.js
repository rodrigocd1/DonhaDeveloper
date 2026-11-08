import { LightningElement, api, track } from 'lwc';
import { isSalesforceMobileApp, buildDisabledFeatureToast, SALESFORCE_APP_DISABLED_MESSAGE } from 'c/communicatorEnvironment';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrCreateGroupThread  from '@salesforce/apex/CommunicatorChatController.getOrCreateGroupThread';
import getMessages             from '@salesforce/apex/CommunicatorChatController.getMessages';
import pollNewMessages         from '@salesforce/apex/CommunicatorChatController.pollNewMessages';
import sendGroupMessage        from '@salesforce/apex/CommunicatorChatController.sendGroupMessage';
import getSettings             from '@salesforce/apex/CommunicatorChatController.getSettings';
import getRepasseIdByOppId     from '@salesforce/apex/CommunicatorChatController.getRepasseIdByOppId';
import getSourceThreadsInfo    from '@salesforce/apex/CommunicatorChatController.getSourceThreadsInfo';
import getAttachmentFile       from '@salesforce/apex/CommunicatorChatController.getAttachmentFile';
import getMessageAttachments   from '@salesforce/apex/CommunicatorChatController.getMessageAttachments';

const DEFAULT_PAGE_SIZE = 10;
const DEFAULT_POLL_MS   = 6000;
const MIN_POLL_MS       = 3000;

const RELATED_REF_NOT_FOUND_LABEL_BY_STAGE = Object.freeze({
    opportunity_negociacao:      'Cotação - Não localizada',
    opportunity_analise_renda:   'AR - Não localizada',
    opportunity_analise_credito: 'AR e AB - Não localizadas'
});

export default class CommunicatorGroupTimeline extends NavigationMixin(LightningElement) {
    @api isModal = false;

    @api
    get groupId() { return this._groupId; }
    set groupId(val) {
        if (val === this._groupId) return;
        this._groupId = val;
        this._reset();
        if (val) this._init();
    }

    @api
    get highlightMessageId() { return this._highlightMessageId; }
    set highlightMessageId(val) {
        this._highlightMessageId = val;
        if (val) this._scrollToHighlighted();
    }

    @track _messages                = [];
    @track _isLoading               = false;
    @track _replyMsgId              = null;
    @track _replyBody               = '';
    @track _isSending               = false;
    @track _sendError               = null;
    @track _collapsedReplyParentIds = [];
    @track _highlightMessageId      = null;
    @track _currentPage             = 1;
    @track _pageSize                = DEFAULT_PAGE_SIZE;
    @track _gotoPageValue           = '';

    _groupId                  = null;
    _groupThreadId            = null;
    _lastTimestamp            = null;
    _pollTimer                = null;
    _pollIntervalMs           = DEFAULT_POLL_MS;
    _isSalesforcePlatformUser = false;
    _sourceThreadMap          = {};

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Lifecycle
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    connectedCallback() {
        this._loadConfig();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Init
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    async _loadConfig() {
        try {
            const settings = await getSettings();
            if (settings.pollingIntervalMs >= MIN_POLL_MS) {
                this._pollIntervalMs = settings.pollingIntervalMs;
            }
            if (settings.threadsPerPage > 0) {
                this._pageSize = settings.threadsPerPage;
            }
            this._isSalesforcePlatformUser = settings.isSalesforcePlatformUser === true;
        } catch (e) { /* keep default */ }
    }

    async _init() {
        if (!this._groupId) return;
        this._isLoading = true;
        try {
            const thread = await getOrCreateGroupThread({ groupId: this._groupId });
            this._groupThreadId = thread.Id;
            this.dispatchEvent(new CustomEvent('threadready', {
                detail: { threadId: thread.Id }
            }));
            await this._loadMessages();
            this._startPolling();
        } catch (e) {
            console.error('[communicatorGroupTimeline] _init:', e);
        } finally {
            this._isLoading = false;
        }
    }

    _scrollToHighlighted() {
        const id = this._highlightMessageId;
        if (!id) return;

        const msg = this._messages.find(m => m.Id === id);

        // For replies, the top-level parent is what pagination tracks.
        const topLevelId = msg?.ParentMessage__c || id;

        // Expand collapsed reply thread if needed.
        if (msg && msg.ParentMessage__c) {
            const parentId = msg.ParentMessage__c;
            if (this._collapsedReplyParentIds.includes(parentId)) {
                this._collapsedReplyParentIds = this._collapsedReplyParentIds.filter(i => i !== parentId);
            }
        }

        // Navigate to the page that contains the message before scrolling.
        const allMessages = this.filteredMessages;
        const topLevelIndex = allMessages.findIndex(m => m.Id === topLevelId);
        if (topLevelIndex >= 0) {
            const targetPage = Math.floor(topLevelIndex / this._pageSize) + 1;
            if (targetPage !== this._currentPage) {
                this._currentPage   = targetPage;
                this._gotoPageValue = String(targetPage);
            }
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector(`[data-msg-id="${id}"]`);
            if (el) {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        }, 200);
    }

    _reset() {
        this._stopPolling();
        this._messages                      = [];
        this._groupThreadId                 = null;
        this._lastTimestamp                 = null;
        this._replyMsgId                    = null;
        this._replyBody                     = '';
        this._sendError                     = null;
        this._highlightMessageId            = null;
        this._sourceThreadMap               = {};
        this._collapsedReplyParentIds       = [];
        this._currentPage                   = 1;
        this._gotoPageValue                 = '';
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Message loading
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    async _loadMessages() {
        if (!this._groupThreadId) return;
        const msgs = await getMessages({
            threadId:  this._groupThreadId,
            pageSize:  2000,
            offsetVal: 0
        });
        const rawMsgs = msgs || [];
        await this._loadSourceThreadsInfo(rawMsgs);
        this._messages      = await this._enrichMessages(rawMsgs);
        this._syncReplyCollapseState();
        this._currentPage   = 1;
        this._gotoPageValue = '1';
        this._lastTimestamp = this._messages.length > 0
            ? this._messages[this._messages.length - 1].SentAt__c
            : null;
    }

    async _loadSourceThreadsInfo(msgs) {
        const ids = [...new Set(
            (msgs || [])
                .filter(m => !!m.SourceThreadId__c && !m.ParentMessage__c)
                .map(m => m.SourceThreadId__c)
                .filter(id => !this._sourceThreadMap[id])
        )];
        if (ids.length === 0) return;
        try {
            const dtos = await getSourceThreadsInfo({ threadIds: ids });
            const updated = { ...this._sourceThreadMap };
            (dtos || []).forEach(dto => {
                updated[dto.threadId] = {
                    canReply:  dto.canReply === true,
                    stageName: dto.stageName || '',
                    opportunityId: dto.opportunityId || null,
                    opportunityName: dto.opportunityName || '',
                    arId: dto.arId || null,
                    arName: dto.arName || '',
                    abId: dto.abId || null,
                    abName: dto.abName || '',
                    quoteId: dto.quoteId || null,
                    quoteName: dto.quoteName || '',
                    resolvedRefType: dto.resolvedRefType || null,
                    resolvedRefId: dto.resolvedRefId || null,
                    resolvedRefName: dto.resolvedRefName || '',
                    resolvedRefObjectApiName: dto.resolvedRefObjectApiName || null
                };
            });
            this._sourceThreadMap = updated;
        } catch (e) {
            console.error('[communicatorGroupTimeline] _loadSourceThreadsInfo:', e);
        }
    }

    async _poll() {
        if (!this._groupThreadId) return;
        try {
            const since = this._lastTimestamp || new Date(0).toISOString();
            const newMsgs = await pollNewMessages({ threadId: this._groupThreadId, lastTimestamp: since });
            if (newMsgs && newMsgs.length > 0) {
                await this._loadSourceThreadsInfo(newMsgs);
                const enriched = await this._enrichMessages(newMsgs);
                this._messages = [...this._messages, ...enriched];
                this._syncReplyCollapseState();
                this._lastTimestamp = enriched[enriched.length - 1].SentAt__c;
            }
        } catch (e) {
            console.error('[communicatorGroupTimeline] _poll:', e);
        }
    }

    _startPolling() {
        this._stopPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => this._poll(), this._pollIntervalMs);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async _enrichMessages(msgs) {
        const attachmentsByMessageId = await this._loadMessageAttachments(msgs);
        return (msgs || []).map(m => {
            const isMention  = !!m.SourceThreadId__c && !m.ParentMessage__c;
            const srcInfo    = isMention ? (this._sourceThreadMap[m.SourceThreadId__c] || {}) : {};
            const mentionStage = isMention ? (m.RecordStatus__c || '') : '';
            const relatedRef = this._resolveSourceRelatedRef(srcInfo);
            const attachments = this._resolveMessageAttachments(m, attachmentsByMessageId);
            return {
                ...m,
                isMentionMessage: isMention,
                isReply:          !!m.ParentMessage__c,
                canReply:         isMention ? (srcInfo.canReply !== false) : false,
                stageName:        mentionStage,
                stageBadgeClass:  this._stageClass(mentionStage),
                opportunityId:    isMention ? (srcInfo.opportunityId || null) : null,
                opportunityName:  isMention ? (srcInfo.opportunityName || 'Acessar oportunidade') : '',
                relatedRefId:             isMention ? relatedRef.id : null,
                relatedRefName:           isMention ? relatedRef.name : '',
                relatedRefType:           isMention ? (relatedRef.type || null) : null,
                relatedRefObjectApiName:  isMention ? relatedRef.objectApiName : null,
                showRelatedRef:           isMention && !!relatedRef.name,
                isRelatedRefClickable:    isMention && !!relatedRef.id,
                senderName:       m.Sender__r?.Name  || m.CreatedBy?.Name  || '',
                senderPhoto:      m.Sender__r?.SmallPhotoUrl || m.CreatedBy?.SmallPhotoUrl || '',
                formattedTime:    m.SentAt__c ? new Date(m.SentAt__c).toLocaleString('pt-BR') : '',
                hasAttachment: attachments.length > 0,
                attachments,
                attachmentDocumentId: attachments.length > 0 ? attachments[0].contentDocumentId : null
            };
        });
    }

    async _loadMessageAttachments(messages) {
        const messageIds = (messages || [])
            .map(message => message?.Id)
            .filter(messageId => !!messageId);
        if (!messageIds.length) return {};

        try {
            const rows = await getMessageAttachments({ messageIds });
            const map = {};
            (rows || []).forEach(row => {
                const messageId = String(row?.messageId || '').trim();
                const contentDocumentId = String(row?.contentDocumentId || '').trim();
                if (!messageId || !contentDocumentId) return;
                if (!map[messageId]) map[messageId] = [];
                map[messageId].push({
                    contentDocumentId,
                    fileName: String(row?.fileName || '').trim() || 'arquivo'
                });
            });
            return map;
        } catch (error) {
            return {};
        }
    }

    _resolveMessageAttachments(message, attachmentsByMessageId) {
        const messageId = String(message?.Id || '').trim();
        const serverAttachments = messageId ? (attachmentsByMessageId?.[messageId] || []) : [];
        if (serverAttachments.length > 0) return serverAttachments;

        const legacyId = String(message?.ContentDocumentId__c || '').trim();
        if (!legacyId) return [];
        return [{
            contentDocumentId: legacyId,
            fileName: 'arquivo'
        }];
    }

    get isAttachmentActionDisabled() {
        return isSalesforceMobileApp();
    }

    get attachmentLinkClass() {
        return this.isAttachmentActionDisabled
            ? 'comm-msg__attachment-link comm-is-disabled'
            : 'comm-msg__attachment-link';
    }

    get attachmentAriaDisabled() {
        return this.isAttachmentActionDisabled ? 'true' : null;
    }

    get attachmentTitle() {
        return this.isAttachmentActionDisabled ? SALESFORCE_APP_DISABLED_MESSAGE : null;
    }

    async handleAttachmentClick(event) {
        event.preventDefault();
        if (this.isAttachmentActionDisabled) {
            this.dispatchEvent(buildDisabledFeatureToast());
            return;
        }
        const contentDocumentId = event.currentTarget?.dataset?.contentDocumentId;
        const messageId = event.currentTarget?.dataset?.messageId;
        const threadId = event.currentTarget?.dataset?.threadId || this._groupThreadId;
        const opportunityId = event.currentTarget?.dataset?.opportunityId || null;
        if (!contentDocumentId) return;
        try {
            const attachment = await getAttachmentFile({
                contentDocumentId,
                contentVersionId: null,
                threadId,
                messageId,
                opportunityId
            });
            this._openAttachmentFromBase64(attachment);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to open attachment', error);
        }
    }

    _openAttachmentFromBase64(attachment) {
        if (!attachment?.base64Data) return;
        const binary = atob(attachment.base64Data);
        const bytes = this._binaryToBytes(binary);
        const mimeType = this._resolveMimeType(attachment.contentType, attachment.fileExtension);
        const blob = new Blob([bytes], { type: mimeType });
        const blobUrl = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = blobUrl;
        anchor.target = '_blank';
        anchor.rel = 'noopener';
        anchor.download = attachment.fileName || 'arquivo';
        anchor.click();
        setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);
    }

    _binaryToBytes(binaryValue) {
        const size = binaryValue.length;
        const buffer = new Uint8Array(size);
        for (let i = 0; i < size; i += 1) {
            buffer[i] = binaryValue.charCodeAt(i);
        }
        return buffer;
    }

    _resolveMimeType(contentType, fileExtension) {
        const ext = String(fileExtension || '').toLowerCase();
        const map = {
            pdf: 'application/pdf',
            png: 'image/png',
            jpg: 'image/jpeg',
            jpeg: 'image/jpeg',
            gif: 'image/gif',
            txt: 'text/plain',
            csv: 'text/csv',
            doc: 'application/msword',
            docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            xls: 'application/vnd.ms-excel',
            xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ppt: 'application/vnd.ms-powerpoint',
            pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            zip: 'application/zip'
        };
        if (map[ext]) return map[ext];
        const normalized = String(contentType || '').toLowerCase();
        return normalized.includes('/') ? normalized : 'application/octet-stream';
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Handlers â€” pagination
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    handleFirstPage() {
        if (this._currentPage <= 1) return;
        this._currentPage   = 1;
        this._gotoPageValue = '1';
    }

    handlePrevPage() {
        if (this._currentPage <= 1) return;
        this._currentPage--;
        this._gotoPageValue = String(this._currentPage);
    }

    handleNextPage() {
        if (this._currentPage >= this.totalPages) return;
        this._currentPage++;
        this._gotoPageValue = String(this._currentPage);
    }

    handleLastPage() {
        if (this._currentPage >= this.totalPages) return;
        this._currentPage   = this.totalPages;
        this._gotoPageValue = String(this._currentPage);
    }

    handlePageSelect(event) {
        const page = Number(event.currentTarget.dataset.page);
        if (!page || page === this._currentPage) return;
        this._currentPage   = page;
        this._gotoPageValue = String(page);
    }

    handleGotoInput(event) {
        this._gotoPageValue = event.target.value;
    }

    handleGotoPage() {
        const page = Number(this._gotoPageValue);
        if (!page) return;
        const target = Math.min(Math.max(page, 1), this.totalPages);
        this._currentPage   = target;
        this._gotoPageValue = String(target);
    }

    handleGotoKeydown(event) {
        if (event.key === 'Enter') this.handleGotoPage();
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Handlers â€” messages
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    handleReplyClick(event) {
        const msgId = event.currentTarget.dataset.msgId;
        if (this._replyMsgId === msgId) {
            this._replyMsgId = null;
            this._replyBody  = '';
            this._sendError  = null;
        } else {
            this._replyMsgId = msgId;
            this._replyBody  = '';
            this._sendError  = null;
        }
    }

    handleReplyInput(event) {
        this._replyBody = event.target.value;
    }

    async handleAccessOpportunity(event) {
        const opportunityId = event.currentTarget?.dataset?.opportunityId;
        if (!opportunityId) return;
        if (this._isSalesforcePlatformUser) {
            try {
                const repasseId = await getRepasseIdByOppId({ opportunityId });
                if (repasseId) {
                    this._navigateToRecord(repasseId, 'Repasse__c');
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Aviso',
                        message: 'Repasse não encontrado para a oportunidade',
                        variant: 'warning'
                    }));
                }
            } catch (e) {
                console.error('communicatorGroupTimeline.handleAccessOpportunity:', e);
            }
            return;
        }
        if (this.isModal) {
            this.dispatchEvent(new CustomEvent('navigatetorecord', {
                detail: { recordId: opportunityId, objectType: 'Opportunity' }
            }));
            return;
        }
        this._navigateToRecord(opportunityId, 'Opportunity');
    }

    handleAccessRelated(event) {
        const recordId = event.currentTarget?.dataset?.recordId;
        const recordName = event.currentTarget?.dataset?.recordName || '';
        const relatedType = event.currentTarget?.dataset?.relatedType || '';
        const objectApiName = event.currentTarget?.dataset?.objectApiName || null;
        if (!recordId) return;
        this._navigateToRecord(recordId, objectApiName, recordName, relatedType);
    }

    handleToggleReplies(event) {
        const parentId = event.currentTarget?.dataset?.parentId;
        if (!parentId) return;

        const collapsed = new Set(this._collapsedReplyParentIds || []);
        if (collapsed.has(parentId)) {
            collapsed.delete(parentId);
        } else {
            collapsed.add(parentId);
        }
        this._collapsedReplyParentIds = [...collapsed];
    }

    handleCancelReply() {
        this._replyMsgId = null;
        this._replyBody  = '';
        this._sendError  = null;
    }

    async handleSendReply() {
        if (!this._replyBody.trim() || !this._replyMsgId || !this._groupId) return;
        this._isSending = true;
        this._sendError = null;
        try {
            await sendGroupMessage({
                groupId:         this._groupId,
                messageBody:     this._replyBody.trim(),
                sourceMessageId: this._replyMsgId
            });
            this._replyMsgId = null;
            this._replyBody  = '';
            await this._poll();
        } catch (e) {
            this._sendError = e.body?.message || e.message || 'Erro ao enviar mensagem.';
        } finally {
            this._isSending = false;
        }
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Computed â€” pagination
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    get totalPages()     { return Math.max(1, Math.ceil(this.filteredMessages.length / this._pageSize)); }
    get firstDisabled()  { return this._currentPage <= 1; }
    get prevDisabled()   { return this._currentPage <= 1; }
    get nextDisabled()   { return this._currentPage >= this.totalPages; }
    get lastDisabled()   { return this._currentPage >= this.totalPages; }
    get showPagination() { return this.filteredMessages.length > 0; }
    get totalLabel()     {
        const n = this.filteredMessages.length;
        return `Total de ${n} ${n === 1 ? 'item' : 'itens'}`;
    }
    get pageSizeLabel()  { return `${this._pageSize} / pág.`; }
    get gotoPageValue()  { return this._gotoPageValue; }

    get paginationItems() {
        const items = [];
        const addPage = page => items.push({
            key: `page-${page}`,
            type: 'page',
            label: String(page),
            page,
            className: page === this._currentPage
                ? 'comm-gtl__page-number comm-gtl__page-number--active'
                : 'comm-gtl__page-number'
        });
        const addEllipsis = key => items.push({ key, type: 'ellipsis', label: '...' });

        if (this.totalPages <= 7) {
            for (let p = 1; p <= this.totalPages; p++) addPage(p);
            return items;
        }

        addPage(1);
        if (this._currentPage > 3) addEllipsis('ellipsis-left');

        const start = Math.max(2, this._currentPage - 1);
        const end   = Math.min(this.totalPages - 1, this._currentPage + 1);
        for (let p = start; p <= end; p++) addPage(p);

        if (this._currentPage < this.totalPages - 2) addEllipsis('ellipsis-right');
        addPage(this.totalPages);

        return items;
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Computed â€” messages
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    get _topLevelMessages() {
        return this._messages.filter(m => !m.ParentMessage__c);
    }

    get filteredMessages() {
        const kw = (this.keyword || '').trim().toLowerCase();
        const filtered = !kw
            ? [...this._topLevelMessages]
            : this._topLevelMessages.filter(m =>
                (m.Body__c || '').toLowerCase().includes(kw) ||
                (m.senderName || '').toLowerCase().includes(kw)
            );
        return filtered.sort((a, b) => {
            const aTs = a?.SentAt__c ? new Date(a.SentAt__c).getTime() : 0;
            const bTs = b?.SentAt__c ? new Date(b.SentAt__c).getTime() : 0;
            return bTs - aTs;
        });
    }

    get paginatedFilteredMessages() {
        const start = (this._currentPage - 1) * this._pageSize;
        return this.filteredMessages.slice(start, start + this._pageSize);
    }

    get hasMessages()      { return this.filteredMessages.length > 0; }
    get isEmpty()          { return !this._isLoading && !this.hasMessages; }

    get messagesWithReplyState() {
        const repliesMap = {};
        this._messages
            .filter(m => !!m.ParentMessage__c)
            .forEach(m => {
                if (!repliesMap[m.ParentMessage__c]) repliesMap[m.ParentMessage__c] = [];
                repliesMap[m.ParentMessage__c].push(m);
            });

        return this.paginatedFilteredMessages.map(m => {
            const highlighted = m.Id === this._highlightMessageId;
            const enrichedReplies = (this._collapsedReplyParentIds.includes(m.Id) ? [] : (repliesMap[m.Id] || []))
                .map(r => ({
                    ...r,
                    isHighlighted: r.Id === this._highlightMessageId,
                    replyClass: r.Id === this._highlightMessageId
                        ? 'comm-gtl__reply-msg comm-gtl__reply-msg--highlight'
                        : 'comm-gtl__reply-msg'
                }));
            return {
                ...m,
                isReplying:    m.Id === this._replyMsgId,
                isHighlighted: highlighted,
                messageClass:  highlighted ? 'comm-gtl__message comm-gtl__message--highlight' : 'comm-gtl__message',
                replies:       enrichedReplies,
                hasReplies:    (repliesMap[m.Id] || []).length > 0,
                isRepliesCollapsed: this._collapsedReplyParentIds.includes(m.Id),
                replyCount:    (repliesMap[m.Id] || []).length,
                toggleRepliesLabel: this._collapsedReplyParentIds.includes(m.Id)
                    ? `Ver ${(repliesMap[m.Id] || []).length} ${(repliesMap[m.Id] || []).length === 1 ? 'resposta' : 'respostas'}`
                    : `Ocultar ${(repliesMap[m.Id] || []).length} ${(repliesMap[m.Id] || []).length === 1 ? 'resposta' : 'respostas'}`
            };
        });
    }

    _syncReplyCollapseState() {
        const repliesMap = {};
        this._messages
            .filter(m => !!m.ParentMessage__c)
            .forEach(m => {
                if (!repliesMap[m.ParentMessage__c]) repliesMap[m.ParentMessage__c] = [];
                repliesMap[m.ParentMessage__c].push(m);
            });

        const parentsWithReplies = new Set(Object.keys(repliesMap));
        const currentCollapsed   = new Set(this._collapsedReplyParentIds || []);
        const nextCollapsed      = new Set();

        currentCollapsed.forEach(parentId => {
            if (parentsWithReplies.has(parentId)) nextCollapsed.add(parentId);
        });

        parentsWithReplies.forEach(parentId => {
            if (!currentCollapsed.has(parentId)) nextCollapsed.add(parentId);
        });

        this._collapsedReplyParentIds = [...nextCollapsed];
    }

    _stageClass(stageName) {
        const s = String(stageName || '').toLowerCase();
        if (!s) return 'comm-gtl__badge comm-gtl__badge--default';
        if (s.includes('apura')) return 'comm-gtl__badge comm-gtl__badge--orange';
        if (s.includes('negocia') || s.includes('anali') || s.includes('aguard') || s.includes('repasse') || s.includes('formu') || s.includes('doss') || s.includes('pend') || s.includes('assin') || s.includes('reten') || s.includes('triag')) {
            return 'comm-gtl__badge comm-gtl__badge--blue';
        }
        if (s.includes('monta') || s.includes('pasta')) return 'comm-gtl__badge comm-gtl__badge--yellow';
        if (s.includes('aprovad') || s.includes('confor') || s.includes('ganha') || s.includes('desembol')) return 'comm-gtl__badge comm-gtl__badge--green';
        if (s.includes('reprovad') || s.includes('cancel')) return 'comm-gtl__badge comm-gtl__badge--red';
        return 'comm-gtl__badge comm-gtl__badge--default';
    }

    _resolveSourceRelatedRef(sourceInfo) {
        const srcInfo = sourceInfo || {};

        if (srcInfo.resolvedRefId && srcInfo.resolvedRefName) {
            const isQuote = srcInfo.resolvedRefType === 'quote' || srcInfo.resolvedRefObjectApiName === 'Quote';
            const name = isQuote ? `Cotação-${srcInfo.resolvedRefName}` : srcInfo.resolvedRefName;
            return { id: srcInfo.resolvedRefId, name, type: srcInfo.resolvedRefType || null, objectApiName: srcInfo.resolvedRefObjectApiName || null };
        }

        const stageType = this._getOpportunityFilterValue(srcInfo.stageName);
        let relatedRef = null;

        if (stageType === 'opportunity_negociacao') {
            if (srcInfo.quoteId && srcInfo.quoteName) {
                relatedRef = { id: srcInfo.quoteId, name: `Cotação-${srcInfo.quoteName}`, type: 'quote', objectApiName: 'Quote' };
            }
        }
        if (!relatedRef && stageType === 'opportunity_analise_credito') {
            if (srcInfo.abId && srcInfo.abName) {
                relatedRef = { id: srcInfo.abId, name: srcInfo.abName, type: 'ab', objectApiName: 'AprovacaoBancaria__c' };
            } else if (srcInfo.arId && srcInfo.arName) {
                relatedRef = { id: srcInfo.arId, name: srcInfo.arName, type: 'ar', objectApiName: 'AnaliseFinanceira__c' };
            }
        }
        if (!relatedRef && (stageType === 'opportunity_montagem_pasta' || stageType === 'opportunity_analise_renda')) {
            if (srcInfo.abId && srcInfo.abName) {
                relatedRef = { id: srcInfo.abId, name: srcInfo.abName, type: 'ab', objectApiName: 'AprovacaoBancaria__c' };
            } else if (srcInfo.arId && srcInfo.arName) {
                relatedRef = { id: srcInfo.arId, name: srcInfo.arName, type: 'ar', objectApiName: 'AnaliseFinanceira__c' };
            }
        }

        if (relatedRef) return relatedRef;

        const notFoundLabel = RELATED_REF_NOT_FOUND_LABEL_BY_STAGE[stageType];
        if (notFoundLabel) {
            return { id: null, name: notFoundLabel, type: null, objectApiName: null };
        }

        return { id: null, name: '', type: null, objectApiName: null };
    }

    _normalizeStatusKey(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[̀-ͯ]/g, '')
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' ');
    }

    _getOpportunityFilterValue(stageName) {
        const status = this._normalizeStatusKey(stageName);
        if (status.includes('montagem de pasta') || status.includes('montagem')) return 'opportunity_montagem_pasta';
        if (status.includes('analise de renda') || status.includes('apuracao de renda')) return 'opportunity_analise_renda';
        if (status.includes('analise de credito') || status.includes('cotacao') || status.includes('cotacoes') || status.includes('aprovacao bancaria')) return 'opportunity_analise_credito';
        if (status.includes('negoci')) return 'opportunity_negociacao';
        if (status.includes('condicao credito') || status.includes('condicao de credito') || status.includes('aprovacao da condicao credito')) return 'opportunity_condicao_credito';
        if (status.includes('condicao comercial') || status.includes('comercial')) return 'opportunity_condicao_comercial';
        if (status.includes('contrato') && !status.includes('assinado') && !status.includes('ganha')) return 'opportunity_contrato';
        if (status.includes('assinado') || status.includes('ganha') || status.includes('desembolsado')) return 'opportunity_ganha';
        return '';
    }

    _navigateToRecord(recordId, objectType, recordName, relatedType) {
        const attributes = {
            recordId,
            actionName: 'view'
        };
        if (objectType) {
            attributes.objectApiName = objectType;
        }
        if (this.isModal) {
            this.dispatchEvent(new CustomEvent('navigatetorecord', {
                detail: { recordId, objectType: objectType || null }
            }));
            return;
        }
        if (this._isBrokerCommunityContext()) {
            if (this._isOpportunityRecord(recordId, objectType)) {
                this._navigateToBrokerCommunityDetail(recordId);
                return;
            }
            if (this._openBrokerCommunityRelatedRecord(relatedType, recordId, recordName)) {
                return;
            }
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes
        });
    }

    _openBrokerCommunityRelatedRecord(type, recordId, recordName) {
        const normalizedType = String(type || '').toLowerCase();
        const basePath = this._normalizeBrokerCommunityBasePath();
        if (normalizedType === 'ar' || normalizedType === 'analise_credito') {
            const slug = this._normalizeAnaliseFinanceiraSlug(recordName);
            window.open(`${basePath}/corretores/s/analisefinanceira/${recordId}${slug ? `/${slug}` : ''}`, '_blank');
            return true;
        }
        if (normalizedType === 'ab') {
            window.open(`${basePath}/corretores/s/detail/${recordId}`, '_blank');
            return true;
        }
        if (normalizedType === 'quote') {
            const slug = this._normalizeCommunityQuoteSlug(recordName);
            window.open(`${basePath}/corretores/s/quote/${recordId}${slug ? `/${encodeURIComponent(slug)}` : ''}`, '_blank');
            return true;
        }
        return false;
    }

    _isOpportunityRecord(recordId, objectType) {
        const normalizedObjectType = String(objectType || '').trim().toLowerCase();
        const normalizedRecordId = String(recordId || '').trim();
        return normalizedObjectType === 'opportunity' || normalizedRecordId.startsWith('006');
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
        const basePath = this._normalizeBrokerCommunityBasePath();
        window.open(`${basePath}/corretores/s/opportunity/${recordId}`, '_blank');
    }

    _normalizeBrokerCommunityBasePath() {
        const pathname = String(window.location?.pathname || '');
        const basePath = pathname.includes('/s/') ? pathname.split('/s/')[0] : pathname;
        return basePath
            .replace(/\/kanban.*$/i, '')
            .replace(/\/+$/, '')
            .replace(/\/corretores$/i, '');
    }

    _normalizeAnaliseFinanceiraSlug(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[̀-ͯ]/g, '')
            .toLowerCase()
            .replace(/[^a-z0-9]/g, '');
    }

    _normalizeCommunityQuoteSlug(value) {
        return String(value || '')
            .normalize('NFC')
            .trim()
            .toLowerCase()
            .replace(/[^0-9a-zÀ-ɏ]+/g, '-')
            .replace(/^-+|-+$/g, '');
    }
}