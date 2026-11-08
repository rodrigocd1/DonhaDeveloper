import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { deleteRecord } from 'lightning/uiRecordApi';
import getBroadcastList from '@salesforce/apex/CommunicatorChatController.getBroadcastList';
import getBroadcastAuthoringContext from '@salesforce/apex/CommunicatorChatController.getBroadcastAuthoringContext';
import getBroadcastThread from '@salesforce/apex/CommunicatorChatController.getBroadcastThread';
import getBroadcastMessages from '@salesforce/apex/CommunicatorChatController.getBroadcastMessages';
import getBroadcastMessageCount from '@salesforce/apex/CommunicatorChatController.getBroadcastMessageCount';
import getBroadcastMessageOffset from '@salesforce/apex/CommunicatorChatController.getBroadcastMessageOffset';
import getBroadcastMessageAttachments from '@salesforce/apex/CommunicatorChatController.getBroadcastMessageAttachments';
import getBroadcastAttachmentFile from '@salesforce/apex/CommunicatorChatController.getBroadcastAttachmentFile';
import pollBroadcastMessages from '@salesforce/apex/CommunicatorChatController.pollBroadcastMessages';
import searchBroadcastMessages from '@salesforce/apex/CommunicatorChatController.searchBroadcastMessages';
import retryBroadcastDistribution from '@salesforce/apex/CommunicatorChatController.retryBroadcastDistribution';
import markBroadcastAsRead from '@salesforce/apex/CommunicatorChatController.markBroadcastAsRead';
import getSettings from '@salesforce/apex/CommunicatorChatController.getSettings';
import { openAttachmentFromBase64 } from 'c/communicatorAttachmentService';

const DEFAULT_LIST_PAGE_SIZE = 20;
const DEFAULT_MESSAGE_PAGE_SIZE = 20;
const MIN_SEARCH_KEYWORD_LEN = 3;
const VIEW_LIST = 'list';
const VIEW_TIMELINE = 'timeline';
const VARIANT_COMPACT = 'compact';
const VARIANT_EXPANDED = 'expanded';

const ACCESS_DENIED_MESSAGE = 'Você não possui acesso a este comunicado.';
const BROADCAST_NOT_FOUND_MESSAGE = 'Comunicado não encontrado ou inativo.';
const BROADCAST_THREAD_NOT_FOUND_MESSAGE = 'Thread de comunicado não encontrado.';
const GENERIC_UNAVAILABLE_MESSAGE = 'Este comunicado nao esta mais disponivel.';
const GENERIC_LIST_ERROR_MESSAGE = 'Não foi possível carregar os comunicados.';
const GENERIC_TIMELINE_ERROR_MESSAGE = 'Não foi possível atualizar o comunicado.';
const GENERIC_SEARCH_ERROR_MESSAGE = 'Não foi possível pesquisar neste comunicado.';
const INLINE_IMAGE_EXTENSIONS = new Set(['jpeg', 'jpg', 'png']);
const INLINE_IMAGE_STATUS_NOT_LOADED = 'notLoaded';
const INLINE_IMAGE_STATUS_LOADING = 'loading';
const INLINE_IMAGE_STATUS_LOADED = 'loaded';
const INLINE_IMAGE_STATUS_ERROR = 'error';
const INLINE_IMAGE_MAX_CONCURRENCY = 3;
const INLINE_IMAGE_ERROR_MESSAGE = 'Não foi possível carregar esta imagem.';
const MESSAGE_STATUS_SENT = 'Sent';
const IMAGE_PREVIEW_ERROR_MESSAGE = 'Não foi possível abrir esta imagem.';

export default class CommunicatorBroadcastWorkspace extends LightningElement {
    _variant = VARIANT_COMPACT;
    _isCommunityContext = false;
    _listPageSize = DEFAULT_LIST_PAGE_SIZE;
    _messagePageSize = DEFAULT_MESSAGE_PAGE_SIZE;
    _isConnected = false;
    _searchSequence = 0;
    _shouldScrollToBottom = false;
    _shouldScrollCompactTimelineToBottom = false;
    _shouldScrollAfterPublish = false;
    _inlineImageCache = new Map();
    _inlineImageQueue = [];
    _activeInlineImageLoads = 0;
    _inlineImageToken = 0;
    _retryingMessageIds = new Set();
    _broadcastReadInFlightThreadId = null;
    _pendingInitialExpandRequest = null;
    _imagePreviewRequestToken = 0;
    _hasPendingImagePreview = false;
    _lastDispatchedView = null;

    @track view = VIEW_LIST;
    @track items = [];
    @track nextCursor = null;
    @track selectedBroadcast = null;
    @track selectedThreadId = null;
    @track messages = [];
    @track messageOffset = 0;
    @track hasMoreMessagesState = false;
    @track pollCursor = null;
    @track searchKeyword = '';
    @track searchResults = [];
    @track isLoadingList = false;
    @track isLoadingMoreList = false;
    @track isLoadingTimeline = false;
    @track isLoadingMoreMessages = false;
    @track isSearching = false;
    @track isDetailsModalOpen = false;
    @track detailsModalMode = 'edit';
    @track canCreateBroadcast = false;
    @track listSearchKeyword = '';
    @track maxUploadBroadcastFileSizeMB = null;
    @track maxClipboardBroadcastImageSizeMB = null;
    @track uploadConfigValid = true;
    @track uploadConfigErrorMessage = '';
    @track listErrorMessage = '';
    @track timelineErrorMessage = '';
    @track searchErrorMessage = '';
    @track refreshInFlight = false;
    @track composerMode = 'publish';
    @track editingMessage = null;
    @track editingAttachmentDraft = null;
    @track messageCount = 0;
    @track isSearchOpen = false;

    requestVersion = 0;

    @api
    get variant() {
        return this._variant;
    }

    set variant(value) {
        const nextVariant = value === VARIANT_EXPANDED ? VARIANT_EXPANDED : VARIANT_COMPACT;
        if (nextVariant === this._variant) return;
        this._variant = nextVariant;
        if (this._isConnected) {
            const version = this._invalidateRequests();
            this._resetBroadcastState({ preserveItems: false });
            this._loadList({
                version,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: false
            }).catch(() => {});
        }
    }

    @api
    get isCommunityContext() {
        return this._isCommunityContext;
    }

    set isCommunityContext(value) {
        this._isCommunityContext = value === true || value === 'true';
    }

    connectedCallback() {
        this._isConnected = true;
        this._initialize().catch(() => {});
    }

    disconnectedCallback() {
        this._isConnected = false;
        this._invalidateRequests();
        this._invalidateImagePreviewRequest({ notifyHost: true });
    }

    renderedCallback() {
        this._notifyViewChangeIfNeeded();

        if (this._pendingInitialExpandRequest?.messageId && this._pendingInitialExpandRequest?.scrollVariant) {
            const timeline = this.template.querySelector('c-communicator-broadcast-timeline');
            if (timeline) {
                const pendingRequest = this._pendingInitialExpandRequest;
                this._pendingInitialExpandRequest = null;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    const targetTimeline = this.template.querySelector('c-communicator-broadcast-timeline');
                    if (!this._isPendingInitialExpandRequestCurrent(pendingRequest, targetTimeline)) return;
                    targetTimeline.expandMessage(pendingRequest.messageId);
                    if (pendingRequest.scrollVariant === VARIANT_COMPACT) {
                        targetTimeline.requestScrollToBottom();
                        return;
                    }
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        if (!this._isPendingInitialExpandRequestCurrent(pendingRequest, targetTimeline)) return;
                        const target = this.template.querySelector('.comm-broadcast-workspace__bottom');
                        if (target) {
                            target.scrollIntoView({ behavior: 'smooth', block: 'end' });
                        }
                    }, 0);
                }, 0);
                return;
            }
        }

        if (this._shouldScrollAfterPublish) {
            if (this._variant === VARIANT_COMPACT) {
                const timeline = this.template.querySelector('c-communicator-broadcast-timeline');
                if (timeline) {
                    this._shouldScrollAfterPublish = false;
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        const targetTimeline = this.template.querySelector('c-communicator-broadcast-timeline');
                        if (targetTimeline) {
                            targetTimeline.scrollToBottom();
                        }
                    }, 0);
                }
            } else {
                const bottom = this.template.querySelector('.comm-broadcast-workspace__bottom');
                if (bottom) {
                    this._shouldScrollAfterPublish = false;
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        const target = this.template.querySelector('.comm-broadcast-workspace__bottom');
                        if (target) {
                            target.scrollIntoView({ behavior: 'smooth', block: 'end' });
                        }
                    }, 0);
                }
            }
        }

        if (this._shouldScrollCompactTimelineToBottom) {
            const timeline = this.template.querySelector('c-communicator-broadcast-timeline');
            if (timeline) {
                this._shouldScrollCompactTimelineToBottom = false;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    const targetTimeline = this.template.querySelector('c-communicator-broadcast-timeline');
                    if (targetTimeline) {
                        targetTimeline.scrollToBottom();
                    }
                }, 0);
            }
        }

        if (this._shouldScrollToBottom) {
            const bottom = this.template.querySelector('.comm-broadcast-workspace__bottom');
            if (!bottom) return;

            this._shouldScrollToBottom = false;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const target = this.template.querySelector('.comm-broadcast-workspace__bottom');
                if (target) {
                    target.scrollIntoView({ behavior: 'smooth', block: 'end' });
                }
            }, 0);
        }
    }

    @api
    async refresh() {
        if (!this._isConnected || this.refreshInFlight) return;
        const version = this.requestVersion;
        this.refreshInFlight = true;
        try {
            if (this.view === VIEW_TIMELINE && this.selectedThreadId) {
                await this._pollTimeline(version);
                return;
            }
            if (this.view === VIEW_TIMELINE && this.selectedBroadcast?.groupId) {
                await this._syncSelectedBroadcast(version, { silentLoading: true });
                return;
            }
            await this._loadList({
                version,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: false,
                silent: true
            });
        } finally {
            if (this._isRequestValid(version)) {
                this.refreshInFlight = false;
            } else {
                this.refreshInFlight = false;
            }
        }
    }

    async _initialize() {
        await this._loadSettings();
        await this._loadAuthoringContext();
        await this._loadList({
            version: this.requestVersion,
            reset: true,
            preserveExistingItems: false,
            preserveErrorMessage: false
        });
    }

    @api
    async openBroadcast(groupId) {
        if (!groupId) return;
        await this._openBroadcast(groupId);
    }

    @api
    openCreateDialog() {
        if (this._variant !== VARIANT_EXPANDED || !this.canCreateBroadcast || this.isDetailsModalOpen) return;
        this.detailsModalMode = 'create';
        this.isDetailsModalOpen = true;
    }

    handleBroadcastAuthoringContext(event) {
        const context = event?.detail || {};
        this.canCreateBroadcast = context.canCreateBroadcast === true;
        this.maxUploadBroadcastFileSizeMB = context.maxUploadBroadcastFileSizeMB ?? null;
        this.maxClipboardBroadcastImageSizeMB = context.maxClipboardBroadcastImageSizeMB ?? null;
        this.uploadConfigValid = context.uploadConfigValid !== false;
        this.uploadConfigErrorMessage = context.uploadConfigErrorMessage || '';
    }

    async handleBroadcastSelect(event) {
        const groupId = event.detail?.groupId;
        if (!groupId) return;
        await this._openBroadcast(groupId);
    }

    async handleLoadMoreList() {
        if (this.isLoadingList || this.isLoadingMoreList || !this.nextCursor) return;
        await this._loadList({
            version: this.requestVersion,
            reset: false,
            preserveExistingItems: true,
            preserveErrorMessage: true
        });
    }

    handleListSearchChange(event) {
        this.listSearchKeyword = String(event?.detail?.keyword || '');
    }

    handleListSearchClear() {
        this.listSearchKeyword = '';
    }

    async handleBackToList() {
        const version = this._invalidateRequests();
        this._resetTimelineState();
        this.view = VIEW_LIST;
        this.timelineErrorMessage = '';
        this.searchErrorMessage = '';
        if (!this.items.length) {
            await this._loadList({
                version,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: false
            });
        }
    }

    async handleLoadMoreMessages() {
        if (
            !this.selectedThreadId ||
            this.isLoadingTimeline ||
            this.isLoadingMoreMessages ||
            this.isSearchActive ||
            !this.hasMoreMessagesState
        ) {
            return;
        }

        const version = this.requestVersion;
        const nextOffset = Math.max(0, this.messageOffset - this._messagePageSize);
        this.template.querySelector('c-communicator-broadcast-timeline')?.capturePrependScrollState();
        this.isLoadingMoreMessages = true;
        this.timelineErrorMessage = '';

        try {
            const rawMessages = await getBroadcastMessages({
                threadId: this.selectedThreadId,
                pageSize: this._messagePageSize,
                offsetVal: nextOffset
            });
            if (!this._isRequestValid(version)) return;

            const normalizedMessages = await this._enrichBroadcastMessages(
                rawMessages,
                version,
                this.selectedThreadId,
                this.selectedBroadcast?.canPublish === true
            );
            if (!this._isRequestValid(version)) return;
            const mergedMessages = this._mergeMessages(normalizedMessages, this.messages);
            this.messages = mergedMessages;
            this.messageOffset = nextOffset;
            this.hasMoreMessagesState = nextOffset > 0;
            this.pollCursor = this._buildPollCursor(mergedMessages);
        } catch (error) {
            if (!this._isRequestValid(version)) return;
            await this._handleTimelineError(error, { fallbackToList: false });
        } finally {
            if (this._isRequestValid(version)) {
                this.isLoadingMoreMessages = false;
            }
        }
    }

    async handleTimelineSearch(event) {
        const keyword = String(event.detail?.keyword || '').trim();
        const version = this.requestVersion;
        this.searchKeyword = keyword;
        this.searchErrorMessage = '';

        if (keyword.length < MIN_SEARCH_KEYWORD_LEN) {
            this._searchSequence += 1;
            this.searchResults = [];
            this.isSearching = false;
            return;
        }

        const searchSequence = ++this._searchSequence;
        this.isSearching = true;

        try {
            if (!this.selectedThreadId) {
                this.searchErrorMessage = GENERIC_SEARCH_ERROR_MESSAGE;
                this.searchResults = [];
                return;
            }

            const rawMessages = await searchBroadcastMessages({
                threadId: this.selectedThreadId,
                keyword
            });
            if (!this._isRequestValid(version) || searchSequence !== this._searchSequence) return;
            this.searchResults = await this._enrichBroadcastMessages(
                rawMessages,
                version,
                this.selectedThreadId,
                this.selectedBroadcast?.canPublish === true
            );
            if (this._variant === VARIANT_COMPACT && this.searchResults.length > 0) {
                this.template.querySelector('c-communicator-broadcast-timeline')?.scrollToTop();
            }
        } catch (error) {
            if (!this._isRequestValid(version) || searchSequence !== this._searchSequence) return;
            await this._handleSearchError(error);
        } finally {
            if (this._isRequestValid(version) && searchSequence === this._searchSequence) {
                this.isSearching = false;
            }
        }
    }

    handleClearSearch() {
        this._clearSearchState({ closePanel: this._variant === VARIANT_COMPACT });
        if (this._variant === VARIANT_COMPACT) {
            this._shouldScrollCompactTimelineToBottom = true;
        }
    }

    handleToggleSearch() {
        if (this.isSearchOpen) {
            this.handleClearSearch();
            return;
        }
        this.isSearchOpen = true;
    }

    _clearSearchState({ closePanel = false } = {}) {
        this._searchSequence += 1;
        this.searchKeyword = '';
        this.searchResults = [];
        this.searchErrorMessage = '';
        this.isSearching = false;
        if (closePanel) {
            this.isSearchOpen = false;
        }
    }

    async handleNavigateToMessage(event) {
        const messageId = String(event.detail?.messageId || '').trim();
        if (!messageId) return;
        await this._navigateToMessage(messageId);
    }

    async handleBroadcastCreated(event) {
        const createdBroadcast = event?.detail?.broadcast || null;
        const groupId = this._extractBroadcastId(createdBroadcast);
        this.isDetailsModalOpen = false;
        this.detailsModalMode = 'edit';
        this.composerMode = 'publish';
        this.editingMessage = null;
        if (!groupId) {
            await this._loadList({
                version: this.requestVersion,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: false,
                silent: true
            });
            return;
        }
        await this._openBroadcast(groupId);
    }

    async handleBroadcastSaved(event) {
        const savedBroadcast = event?.detail?.broadcast || null;
        const groupId = this._extractBroadcastId(savedBroadcast);
        this.isDetailsModalOpen = false;
        this.detailsModalMode = 'edit';
        if (groupId) {
            this._mergeSelectedBroadcastSnapshot(savedBroadcast);
            await this._loadList({
                version: this.requestVersion,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: true,
                silent: true
            });
        }
    }

    async handleBroadcastArchived(event) {
        const archivedBroadcast = event?.detail?.broadcast || null;
        const groupId = this._extractBroadcastId(archivedBroadcast);
        this.isDetailsModalOpen = false;
        this.detailsModalMode = 'edit';

        if (this.selectedBroadcast?.groupId === groupId) {
            this._resetTimelineState();
            this.view = VIEW_LIST;
        }

        await this._loadList({
            version: this._invalidateRequests(),
            reset: true,
            preserveExistingItems: false,
            preserveErrorMessage: false,
            silent: true
        });
    }

    async handleBroadcastPublished(event) {
        const publishedMessage = event?.detail?.message || null;
        if (!publishedMessage?.Id) return;

        const version = this.requestVersion;
        const threadId = publishedMessage.threadId || this.selectedThreadId || null;
        const enrichedMessages = await this._enrichBroadcastMessages(
            [publishedMessage],
            version,
            threadId,
            this.selectedBroadcast?.canPublish === true
        );
        if (!this._isRequestValid(version) || !enrichedMessages.length) return;

        const message = enrichedMessages[0];
        this.selectedThreadId = threadId || message.threadId || this.selectedThreadId;
        const previousMessageCount = this.messages.length;
        this.messages = this._mergeMessages(this.messages, enrichedMessages);
        this.messageCount += Math.max(0, this.messages.length - previousMessageCount);
        this.pollCursor = this._buildPollCursor(this.messages);
        if (!this.selectedThreadId) {
            this.hasMoreMessagesState = false;
        }

        this._mergeSelectedBroadcastSnapshot({
            groupId: this.selectedBroadcast?.groupId || event?.detail?.groupId || null,
            threadId: this.selectedThreadId,
            broadcastLastActivityAt: message.status === MESSAGE_STATUS_SENT ? message.sentAt : null,
            lastMessageAt: message.status === MESSAGE_STATUS_SENT ? message.sentAt : null
        });
        this._requestScrollAfterPublish();
        this.composerMode = 'publish';
        this.editingMessage = null;
        await this._loadList({
            version,
            reset: true,
            preserveExistingItems: false,
            preserveErrorMessage: true,
            silent: true
        });
    }

    async handleBroadcastSaveEdit(event) {
        const editedMessage = event?.detail?.message || null;
        if (!editedMessage?.Id) return;
        const removedContentDocumentIds = Array.isArray(event?.detail?.removedContentDocumentIds)
            ? event.detail.removedContentDocumentIds
            : [];
        this._dropInlineImageCacheEntries(removedContentDocumentIds);

        const version = this.requestVersion;
        const threadId = editedMessage.threadId || this.selectedThreadId || null;
        const enrichedMessages = await this._enrichBroadcastMessages(
            [editedMessage],
            version,
            threadId,
            this.selectedBroadcast?.canPublish === true
        );
        if (!this._isRequestValid(version) || !enrichedMessages.length) return;

        this._replaceMessageInTimeline(enrichedMessages[0]);
        this.composerMode = 'publish';
        this.editingMessage = null;
        this.editingAttachmentDraft = null;
        if (this.isSearchActive) {
            await this.handleTimelineSearch({ detail: { keyword: this.searchKeyword } });
        }
    }

    async handleBroadcastCancelEdit() {
        const temporaryAttachments = this.editingAttachmentDraft?.newAttachments || [];
        try {
            await this._deleteTemporaryAttachments(temporaryAttachments);
        } catch (error) {
            const message = this._normalizeError(error) || 'Não foi possível limpar os anexos temporários.';
            this.timelineErrorMessage = message;
            this._showToast('Erro', message, 'error');
            return;
        }
        this.composerMode = 'publish';
        this.editingMessage = null;
        this.editingAttachmentDraft = null;
    }

    handleBroadcastModalClose() {
        this.isDetailsModalOpen = false;
        this.detailsModalMode = 'edit';
    }

    handleBroadcastDetails(event) {
        if (this._variant !== VARIANT_EXPANDED) return;
        if (!this.selectedBroadcast?.groupId || !this.selectedBroadcast.canPublish) return;
        const groupId = String(event?.detail?.groupId || this.selectedBroadcast.groupId || '').trim();
        if (!groupId) return;
        this.detailsModalMode = 'edit';
        this.isDetailsModalOpen = true;
    }

    handleBroadcastEditMessage(event) {
        const message = event?.detail?.message || null;
        if (!message?.Id || !message?.canEdit) return;
        if (this.editingMessage?.Id && this.editingMessage.Id !== message.Id) return;
        this.composerMode = 'edit';
        this.editingAttachmentDraft = this._buildEditingAttachmentDraft(message);
        this.editingMessage = { ...message };
        this.timelineErrorMessage = '';
    }

    handleBroadcastEditBlocked(event) {
        const message = String(event?.detail?.message || '').trim();
        if (!message) return;
        this._showToast('Erro', message, 'error');
    }

    async handleBroadcastRetryMessage(event) {
        const messageId = String(event?.detail?.messageId || '').trim();
        if (!messageId || this._isRetryingMessage(messageId)) return;

        const version = this.requestVersion;
        this.timelineErrorMessage = '';
        this._setRetryingMessageState(messageId, true);
        try {
            const retriedMessage = await retryBroadcastDistribution({ messageId });
            if (!this._isRequestValid(version) || !retriedMessage?.Id) {
                this._setRetryingMessageState(messageId, false);
                return;
            }

            const threadId = retriedMessage.threadId || this.selectedThreadId || null;
            const enrichedMessages = await this._enrichBroadcastMessages(
                [retriedMessage],
                version,
                threadId,
                this.selectedBroadcast?.canPublish === true
            );
            if (!this._isRequestValid(version) || !enrichedMessages.length) {
                this._setRetryingMessageState(messageId, false);
                return;
            }

            this._setRetryingMessageState(messageId, false);
            this._replaceMessageInTimeline({
                ...enrichedMessages[0],
                isRetrying: false
            });
            this._showToast(
                'Sucesso',
                'Publicação reenfileirada com sucesso. A distribuição será retomada em segundo plano.',
                'success'
            );
        } catch (error) {
            this._setRetryingMessageState(messageId, false);
            if (!this._isRequestValid(version)) return;
            const message = this._normalizeError(error) || GENERIC_TIMELINE_ERROR_MESSAGE;
            this.timelineErrorMessage = message;
            this._showToast('Erro', message, 'error');
        }
    }

    handleBroadcastEditAttachmentsAdded(event) {
        if (!this.editingAttachmentDraft || !this.editingMessage?.Id) return;
        const files = Array.isArray(event?.detail?.files) ? event.detail.files : [];
        if (!files.length) return;

        const existingIds = new Set([
            ...(this.editingAttachmentDraft.originalAttachments || []).map(file => file.documentId),
            ...(this.editingAttachmentDraft.newAttachments || []).map(file => file.documentId)
        ]);
        const nextNewAttachments = [...(this.editingAttachmentDraft.newAttachments || [])];
        files.forEach(file => {
            const documentId = String(file?.documentId || '').trim();
            if (!documentId || existingIds.has(documentId)) return;
            existingIds.add(documentId);
            nextNewAttachments.push({
                localId: file.localId || `broadcast-edit-new-${documentId}`,
                documentId,
                fileName: String(file?.fileName || '').trim() || 'arquivo',
                fileExtension: String(file?.fileExtension || '').trim(),
                origin: 'new'
            });
        });
        this._setEditingAttachmentDraft({
            ...this.editingAttachmentDraft,
            newAttachments: nextNewAttachments
        });
    }

    async handleBroadcastEditAttachmentRemove(event) {
        if (!this.editingAttachmentDraft || !this.editingMessage?.Id) return;
        const documentId = String(event?.detail?.documentId || '').trim();
        const origin = String(event?.detail?.origin || '').trim();
        if (!documentId) return;

        if (origin === 'new') {
            const target = (this.editingAttachmentDraft.newAttachments || [])
                .find(file => file.documentId === documentId);
            if (!target) return;
            try {
                await this._deleteTemporaryAttachments([target]);
                this._setEditingAttachmentDraft({
                    ...this.editingAttachmentDraft,
                    newAttachments: (this.editingAttachmentDraft.newAttachments || [])
                        .filter(file => file.documentId !== documentId)
                });
                this.timelineErrorMessage = '';
            } catch (error) {
                const message = this._normalizeError(error) || 'Não foi possível remover o anexo.';
                this.timelineErrorMessage = message;
                this._showToast('Erro', message, 'error');
            }
            return;
        }

        const originalExists = (this.editingAttachmentDraft.originalAttachments || [])
            .some(file => file.documentId === documentId);
        if (!originalExists) return;
        const removed = new Set(this.editingAttachmentDraft.removedOriginalAttachmentIds || []);
        removed.add(documentId);
        this._setEditingAttachmentDraft({
            ...this.editingAttachmentDraft,
            removedOriginalAttachmentIds: Array.from(removed)
        });
        this.timelineErrorMessage = '';
    }

    async handleBroadcastAttachmentClick(event) {
        const contentDocumentId = String(event?.detail?.contentDocumentId || '').trim();
        const messageId = String(event?.detail?.messageId || '').trim();
        const threadId = String(event?.detail?.threadId || this.selectedThreadId || '').trim();
        if (!contentDocumentId || !threadId) return;

        this.timelineErrorMessage = '';
        this._invalidateImagePreviewRequest({ notifyHost: true });

        const attachmentMeta = this._findAttachmentMetadata(messageId, contentDocumentId);
        const fileExtension = this._normalizeFileExtension(
            event?.detail?.fileExtension || attachmentMeta?.fileExtension
        );
        const fileName = String(
            event?.detail?.fileName || attachmentMeta?.fileName || 'arquivo'
        ).trim() || 'arquivo';

        if (this._isInlineImageExtension(fileExtension)) {
            const requestToken = this._beginImagePreviewRequest();
            if (attachmentMeta?.inlineSrc) {
                this._dispatchImagePreviewOpen({
                    src: attachmentMeta.inlineSrc,
                    fileName
                });
                return;
            }

            try {
                const attachment = await getBroadcastAttachmentFile({
                    threadId,
                    messageId: messageId || null,
                    contentDocumentId,
                    contentVersionId: null
                });
                if (!this._isImagePreviewRequestCurrent(requestToken)) return;

                const resolvedExtension = this._normalizeFileExtension(
                    attachment?.fileExtension || fileExtension
                );
                if (!this._isInlineImageExtension(resolvedExtension) || !attachment?.base64Data) {
                    this._handleImagePreviewError(IMAGE_PREVIEW_ERROR_MESSAGE, requestToken);
                    return;
                }

                const contentType = this._resolveInlineImageMimeType(
                    attachment?.contentType,
                    resolvedExtension
                );
                this._dispatchImagePreviewOpen({
                    src: `data:${contentType};base64,${attachment.base64Data}`,
                    fileName: String(attachment?.fileName || fileName).trim() || fileName
                });
            } catch (error) {
                this._handleImagePreviewError(
                    this._normalizeError(error) || IMAGE_PREVIEW_ERROR_MESSAGE,
                    requestToken
                );
            }
            return;
        }

        try {
            const attachment = await getBroadcastAttachmentFile({
                threadId,
                messageId: messageId || null,
                contentDocumentId,
                contentVersionId: null
            });
            openAttachmentFromBase64(attachment);
        } catch (error) {
            this.timelineErrorMessage = this._normalizeError(error) || GENERIC_TIMELINE_ERROR_MESSAGE;
        }
    }

    handleLoadInlineImages(event) {
        const requested = Array.isArray(event?.detail?.attachments)
            ? event.detail.attachments
            : [];
        if (!requested.length || !this.selectedThreadId) return;

        let queued = false;
        requested.forEach(item => {
            const contentDocumentId = String(item?.contentDocumentId || '').trim();
            const messageId = String(item?.messageId || '').trim();
            const threadId = String(item?.threadId || this.selectedThreadId || '').trim();
            const fileExtension = this._normalizeFileExtension(item?.fileExtension);
            if (!contentDocumentId || !messageId || threadId !== this.selectedThreadId) return;
            if (!this._isInlineImageExtension(fileExtension)) return;

            const cached = this._inlineImageCache.get(contentDocumentId);
            if (cached?.status === INLINE_IMAGE_STATUS_LOADING || cached?.status === INLINE_IMAGE_STATUS_LOADED) return;
            if (cached?.status === INLINE_IMAGE_STATUS_ERROR) return;

            this._inlineImageCache.set(contentDocumentId, {
                status: INLINE_IMAGE_STATUS_LOADING,
                fileName: String(item?.fileName || '').trim() || 'arquivo',
                fileExtension,
                errorMessage: ''
            });
            this._inlineImageQueue.push({
                contentDocumentId,
                messageId,
                threadId,
                fileName: String(item?.fileName || '').trim() || 'arquivo',
                fileExtension,
                token: this._inlineImageToken
            });
            queued = true;
        });

        if (!queued) return;
        this._refreshInlineAttachmentState();
        this._drainInlineImageQueue();
    }

    async _loadList({ version, reset, preserveExistingItems, preserveErrorMessage, silent = false }) {
        const activeVersion = version ?? this.requestVersion;
        if (!this._isRequestValid(activeVersion)) return;

        if (reset) {
            if (!silent) {
                this.isLoadingList = true;
            }
        } else if (!silent) {
            this.isLoadingMoreList = true;
        }

        if (!preserveErrorMessage && !silent) {
            this.listErrorMessage = '';
        }

        try {
            const response = await getBroadcastList({
                pageSize: this._listPageSize,
                cursor: reset ? null : this.nextCursor
            });
            if (!this._isRequestValid(activeVersion)) return;

            const normalizedItems = this._normalizeBroadcastItems(response?.items);
            const currentItems = preserveExistingItems ? this.items : [];
            this.items = reset
                ? this._mergeBroadcastItems(normalizedItems, currentItems)
                : this._mergeBroadcastItems(currentItems, normalizedItems);
            this.nextCursor = response?.nextCursor || null;
            if (!preserveErrorMessage) {
                this.listErrorMessage = '';
            }
        } catch (error) {
            if (!this._isRequestValid(activeVersion)) return;
            this.listErrorMessage = this._normalizeError(error) || GENERIC_LIST_ERROR_MESSAGE;
        } finally {
            if (this._isRequestValid(activeVersion)) {
                if (!silent) {
                    this.isLoadingList = false;
                    this.isLoadingMoreList = false;
                }
            }
        }
    }

    async _loadAuthoringContext() {
        try {
            const context = await getBroadcastAuthoringContext();
            this.canCreateBroadcast = context?.canCreateBroadcast === true;
            this.maxUploadBroadcastFileSizeMB = context?.maxUploadBroadcastFileSizeMB ?? null;
            this.maxClipboardBroadcastImageSizeMB = context?.maxClipboardBroadcastImageSizeMB ?? null;
            this.uploadConfigValid = context?.uploadConfigValid !== false;
            this.uploadConfigErrorMessage = context?.uploadConfigErrorMessage || '';
        } catch (error) {
            this.canCreateBroadcast = false;
            this.maxUploadBroadcastFileSizeMB = null;
            this.maxClipboardBroadcastImageSizeMB = null;
            this.uploadConfigValid = false;
            this.uploadConfigErrorMessage =
                this._normalizeError(error) || 'Não foi possível carregar a configuração do comunicado.';
        } finally {
            this._dispatchAuthoringContext();
        }
    }

    async _loadSettings() {
        try {
            const settings = await getSettings();
            if (settings?.messagesPerPage > 0) {
                this._messagePageSize = settings.messagesPerPage;
            }
        } catch (error) {
            // Keep safe defaults when config is temporarily unavailable.
        }
    }

    _dispatchAuthoringContext() {
        this.dispatchEvent(new CustomEvent('broadcastauthoringcontext', {
            detail: {
                canCreateBroadcast: this.canCreateBroadcast === true,
                maxUploadBroadcastFileSizeMB: this.maxUploadBroadcastFileSizeMB,
                maxClipboardBroadcastImageSizeMB: this.maxClipboardBroadcastImageSizeMB,
                uploadConfigValid: this.uploadConfigValid !== false,
                uploadConfigErrorMessage: this.uploadConfigErrorMessage || ''
            }
        }));
    }

    async _openBroadcast(groupId) {
        if (!groupId) return;
        const version = this._invalidateRequests();
        this.view = VIEW_TIMELINE;
        this._resetTimelineState();
        this.view = VIEW_TIMELINE;
        this.isLoadingTimeline = true;

        try {
            const state = await this._loadSelectedBroadcastState(groupId, version, {
                loadAllMessages: this._variant === VARIANT_COMPACT
            });
            if (!this._isRequestValid(version) || !state) return;
            this._applySelectedBroadcastState(state);
            this._prepareInitialExpandMessage(state.messages);
            this._requestInitialBroadcastScroll();
        } catch (error) {
            if (!this._isRequestValid(version)) return;
            await this._handleOpenError(error);
            return;
        } finally {
            if (this._isRequestValid(version)) {
                this.isLoadingTimeline = false;
            }
        }

        if (!this._isRequestValid(version)) return;
        if (!this.selectedThreadId) {
            await this._loadList({
                version,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: true,
                silent: true
            });
            return;
        }
        await this._markSelectedBroadcastAsRead(version, this.selectedThreadId);
        await this._loadList({
            version,
            reset: true,
            preserveExistingItems: false,
            preserveErrorMessage: false,
            silent: true
        });
    }

    async _syncSelectedBroadcast(version, { silentLoading = false } = {}) {
        const groupId = this.selectedBroadcast?.groupId;
        if (!groupId) return;
        if (!this._isRequestValid(version)) return;

        if (!silentLoading) {
            this.isLoadingTimeline = true;
        }
        try {
            const state = await this._loadSelectedBroadcastState(groupId, version, {
                loadAllMessages: this._variant === VARIANT_COMPACT
            });
            if (!this._isRequestValid(version) || !state) return;
            this._applySelectedBroadcastState(state);
            this._requestInitialBroadcastScroll();
        } catch (error) {
            if (!this._isRequestValid(version)) return;
            await this._handleTimelineError(error, { fallbackToList: true });
            return;
        } finally {
            if (this._isRequestValid(version) && !silentLoading) {
                this.isLoadingTimeline = false;
            }
        }

        if (!this._isRequestValid(version) || !this.selectedThreadId) {
            await this._loadList({
                version,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: true,
                silent: true
            });
            return;
        }

        await this._markSelectedBroadcastAsRead(version, this.selectedThreadId);
        await this._loadList({
            version,
            reset: true,
            preserveExistingItems: false,
            preserveErrorMessage: true,
            silent: true
        });
    }

    async _loadSelectedBroadcastState(groupId, version, { loadAllMessages = false } = {}) {
        const seedBroadcast = this.items.find(item => item.groupId === groupId) || this.selectedBroadcast || null;
        const threadResponse = await getBroadcastThread({ broadcastGroupId: groupId });
        if (!this._isRequestValid(version)) return null;

        const broadcast = this._normalizeBroadcastItem(threadResponse?.broadcast || seedBroadcast);
        if (!broadcast) {
            throw new Error(BROADCAST_NOT_FOUND_MESSAGE);
        }

        const threadId = threadResponse?.thread?.Id || broadcast?.threadId || null;
        let messages = [];
        let messageCount = 0;
        let messageOffset = 0;
        let hasMoreMessagesState = false;
        let pollCursor = null;

        if (threadId) {
            const totalCount = await getBroadcastMessageCount({ threadId });
            if (!this._isRequestValid(version)) return null;
            messageCount = Math.max(0, Number(totalCount) || 0);
            const initialOffset = loadAllMessages ? 0 : Math.max(0, messageCount - this._messagePageSize);
            const pageSize = loadAllMessages ? Math.max(1, messageCount || this._messagePageSize) : this._messagePageSize;

            const rawMessages = await getBroadcastMessages({
                threadId,
                pageSize,
                offsetVal: initialOffset
            });
            if (!this._isRequestValid(version)) return null;

            messages = await this._enrichBroadcastMessages(
                rawMessages,
                version,
                threadId,
                broadcast.canPublish === true
            );
            if (!this._isRequestValid(version)) return null;

            messageOffset = initialOffset;
            hasMoreMessagesState = loadAllMessages ? false : initialOffset > 0;
            pollCursor = this._buildPollCursor(messages);
        }

        return {
            broadcast,
            threadId,
            messages,
            messageCount,
            messageOffset,
            hasMoreMessagesState,
            pollCursor
        };
    }

    async _enrichBroadcastMessages(rawMessages, version, threadId, canManageBroadcast = false) {
        const normalizedMessages = this._normalizeMessages(rawMessages, canManageBroadcast);
        if (!normalizedMessages.length) return normalizedMessages;

        let attachmentsByMessageId = {};
        if (normalizedMessages.some(message => message?.hasAttachment === true)) {
            attachmentsByMessageId = await this._loadBroadcastAttachments(
                threadId,
                normalizedMessages,
                version
            );
            if (!this._isRequestValid(version)) return [];
        }

        const enrichedMessages = normalizedMessages.map(message => {
            const attachments = attachmentsByMessageId[message.Id] || [];
            return {
                ...message,
                attachments,
                hasAttachment: attachments.length > 0 || message.hasAttachment === true
            };
        });
        return this._applyInlineAttachmentState(enrichedMessages);
    }

    async _loadBroadcastAttachments(threadId, messages, version) {
        const result = {};
        const messageIds = (messages || [])
            .map(message => message?.Id)
            .filter(messageId => !!messageId);
        if (!threadId || !messageIds.length) return result;

        try {
            const rows = await getBroadcastMessageAttachments({
                threadId,
                messageIds
            });
            if (!this._isRequestValid(version)) return {};

            (rows || []).forEach(row => {
                const messageId = String(row?.messageId || '').trim();
                const contentDocumentId = String(row?.contentDocumentId || '').trim();
                if (!messageId || !contentDocumentId) return;
                if (!result[messageId]) result[messageId] = [];
                result[messageId].push({
                    contentDocumentId,
                    fileName: String(row?.fileName || '').trim() || 'arquivo',
                    fileExtension: this._normalizeFileExtension(row?.fileExtension)
                });
            });
        } catch (error) {
            return {};
        }

        return result;
    }

    _drainInlineImageQueue() {
        while (this._activeInlineImageLoads < INLINE_IMAGE_MAX_CONCURRENCY && this._inlineImageQueue.length) {
            const request = this._inlineImageQueue.shift();
            if (!this._isInlineImageRequestCurrent(request)) continue;
            this._loadInlineImage(request);
        }
    }

    async _loadInlineImage(request) {
        this._activeInlineImageLoads += 1;
        try {
            const attachment = await getBroadcastAttachmentFile({
                threadId: request.threadId,
                messageId: request.messageId,
                contentDocumentId: request.contentDocumentId,
                contentVersionId: null
            });
            if (!this._isInlineImageRequestCurrent(request)) return;

            const fileExtension = this._normalizeFileExtension(
                attachment?.fileExtension || request.fileExtension
            );
            if (!this._isInlineImageExtension(fileExtension) || !attachment?.base64Data) {
                this._inlineImageCache.set(request.contentDocumentId, {
                    status: INLINE_IMAGE_STATUS_ERROR,
                    fileName: request.fileName,
                    fileExtension,
                    errorMessage: INLINE_IMAGE_ERROR_MESSAGE
                });
                return;
            }

            const contentType = this._resolveInlineImageMimeType(attachment?.contentType, fileExtension);
            this._inlineImageCache.set(request.contentDocumentId, {
                status: INLINE_IMAGE_STATUS_LOADED,
                fileName: String(attachment?.fileName || request.fileName || '').trim() || 'arquivo',
                fileExtension,
                contentType,
                base64Data: attachment.base64Data,
                src: `data:${contentType};base64,${attachment.base64Data}`,
                errorMessage: ''
            });
        } catch (error) {
            if (!this._isInlineImageRequestCurrent(request)) return;
            this._inlineImageCache.set(request.contentDocumentId, {
                status: INLINE_IMAGE_STATUS_ERROR,
                fileName: request.fileName,
                fileExtension: request.fileExtension,
                errorMessage: this._normalizeError(error) || INLINE_IMAGE_ERROR_MESSAGE
            });
        } finally {
            this._activeInlineImageLoads = Math.max(0, this._activeInlineImageLoads - 1);
            this._refreshInlineAttachmentState();
            this._drainInlineImageQueue();
        }
    }

    _isInlineImageRequestCurrent(request) {
        return request?.token === this._inlineImageToken
            && request.threadId === this.selectedThreadId
            && this._isAttachmentStillReferenced(request.contentDocumentId);
    }

    _isAttachmentStillReferenced(contentDocumentId) {
        if (!contentDocumentId) return false;
        const allMessages = [
            ...(this.messages || []),
            ...(this.searchResults || [])
        ];
        return allMessages.some(message => (message?.attachments || []).some(
            attachment => attachment?.contentDocumentId === contentDocumentId
        ));
    }

    _refreshInlineAttachmentState() {
        this.messages = this._applyInlineAttachmentState(this.messages);
        if (this.searchResults.length) {
            this.searchResults = this._applyInlineAttachmentState(this.searchResults);
        }
        this._pruneInlineImageCache();
    }

    _applyInlineAttachmentState(messages) {
        return (messages || []).map(message => ({
            ...message,
            attachments: (message.attachments || []).map(attachment => {
                const fileExtension = this._normalizeFileExtension(attachment?.fileExtension);
                const isInlineImage = this._isInlineImageExtension(fileExtension);
                const cached = this._inlineImageCache.get(attachment?.contentDocumentId);
                return {
                    ...attachment,
                    fileExtension,
                    isInlineImage,
                    inlineStatus: isInlineImage
                        ? (cached?.status || INLINE_IMAGE_STATUS_NOT_LOADED)
                        : INLINE_IMAGE_STATUS_NOT_LOADED,
                    inlineSrc: cached?.src || '',
                    inlineErrorMessage: cached?.errorMessage || ''
                };
            })
        }));
    }

    _pruneInlineImageCache() {
        if (!this._inlineImageCache.size) return;
        const referencedDocumentIds = new Set();
        [
            ...(this.messages || []),
            ...(this.searchResults || [])
        ].forEach(message => {
            (message?.attachments || []).forEach(attachment => {
                if (attachment?.contentDocumentId) {
                    referencedDocumentIds.add(attachment.contentDocumentId);
                }
            });
        });
        Array.from(this._inlineImageCache.keys()).forEach(contentDocumentId => {
            if (!referencedDocumentIds.has(contentDocumentId)) {
                this._inlineImageCache.delete(contentDocumentId);
            }
        });
    }

    _dropInlineImageCacheEntries(contentDocumentIds) {
        (contentDocumentIds || []).forEach(contentDocumentId => {
            const key = String(contentDocumentId || '').trim();
            if (key) this._inlineImageCache.delete(key);
        });
    }

    _resetInlineImageCache() {
        this._inlineImageToken += 1;
        this._inlineImageCache = new Map();
        this._inlineImageQueue = [];
        this._activeInlineImageLoads = 0;
    }

    _normalizeFileExtension(value) {
        return String(value || '').trim().toLowerCase();
    }

    _isInlineImageExtension(fileExtension) {
        return INLINE_IMAGE_EXTENSIONS.has(this._normalizeFileExtension(fileExtension));
    }

    _resolveInlineImageMimeType(contentType, fileExtension) {
        const normalizedContentType = String(contentType || '').trim().toLowerCase();
        if (normalizedContentType.includes('/') && normalizedContentType.startsWith('image/')) {
            return normalizedContentType;
        }
        return this._normalizeFileExtension(fileExtension) === 'png'
            ? 'image/png'
            : 'image/jpeg';
    }

    _applySelectedBroadcastState(state) {
        this._invalidateImagePreviewRequest({ notifyHost: true });
        this._resetInlineImageCache();
        this.selectedBroadcast = state.broadcast;
        this.selectedThreadId = state.threadId;
        this.messages = this._applyInlineAttachmentState(state.messages);
        this.messageCount = state.messageCount || 0;
        this.messageOffset = state.messageOffset;
        this.hasMoreMessagesState = state.hasMoreMessagesState;
        this.pollCursor = state.pollCursor;
        this.searchKeyword = '';
        this.searchResults = [];
        this.timelineErrorMessage = '';
        this.searchErrorMessage = '';
        this.composerMode = 'publish';
        this.editingMessage = null;
        this.editingAttachmentDraft = null;
        this._pendingInitialExpandRequest = null;
    }

    _mergeSelectedBroadcastSnapshot(snapshot) {
        const groupId = this._extractBroadcastId(snapshot) || this.selectedBroadcast?.groupId || null;
        if (!groupId) return;

        const base = this.selectedBroadcast?.groupId === groupId
            ? { ...this.selectedBroadcast }
            : { groupId };
        const nextActivityAt = snapshot?.broadcastLastActivityAt
            || snapshot?.BroadcastLastActivityAt__c
            || snapshot?.lastMessageAt
            || snapshot?.LastMessageAt__c
            || base.broadcastLastActivityAt
            || base.lastMessageAt
            || null;

        base.groupId = groupId;
        base.groupName = snapshot?.groupName || snapshot?.Name || base.groupName || '';
        base.description = snapshot?.description || snapshot?.Description__c || base.description || '';
        base.createdByUserId = snapshot?.createdByUserId || snapshot?.CreatedByUser__c || base.createdByUserId || null;
        base.createdByUserName = snapshot?.createdByUserName || snapshot?.CreatedByUser__r?.Name || base.createdByUserName || '';
        base.createdByUserPhotoUrl = snapshot?.createdByUserPhotoUrl
            || snapshot?.CreatedByUser__r?.SmallPhotoUrl
            || base.createdByUserPhotoUrl
            || '';
        base.creatorInitial = this._buildInitial(base.createdByUserName || base.groupName || 'C');
        base.threadId = snapshot?.threadId || snapshot?.thread?.Id || base.threadId || null;
        base.broadcastLastActivityAt = nextActivityAt;
        base.lastMessageAt = nextActivityAt;
        base.unreadCount = snapshot?.unreadCount != null ? snapshot.unreadCount : base.unreadCount || 0;
        if (snapshot?.canPublish != null) {
            base.canPublish = snapshot.canPublish === true;
        }

        this.selectedBroadcast = base;
    }

    _replaceMessageInTimeline(message) {
        if (!message?.Id) return;
        this.messages = this._mergeMessages(this.messages, [message]);
        if (this.isSearchActive) {
            const searchMessageIds = new Set((this.searchResults || []).map(item => item.Id));
            if (searchMessageIds.has(message.Id)) {
                this.searchResults = this._mergeMessages(this.searchResults, [message]);
            }
        }
        this.pollCursor = this._buildPollCursor(this.messages);
    }

    _isRetryingMessage(messageId) {
        const normalizedMessageId = String(messageId || '').trim();
        return normalizedMessageId ? this._retryingMessageIds.has(normalizedMessageId) : false;
    }

    _setRetryingMessageState(messageId, isRetrying) {
        const normalizedMessageId = String(messageId || '').trim();
        if (!normalizedMessageId) return;

        const retryingMessageIds = new Set(this._retryingMessageIds);
        const isAlreadyRetrying = retryingMessageIds.has(normalizedMessageId);
        if (isRetrying === isAlreadyRetrying) return;

        if (isRetrying) {
            retryingMessageIds.add(normalizedMessageId);
        } else {
            retryingMessageIds.delete(normalizedMessageId);
        }

        this._retryingMessageIds = retryingMessageIds;
        this.messages = this._applyRetryingState(this.messages);
        this.searchResults = this._applyRetryingState(this.searchResults);
    }

    _applyRetryingState(messages) {
        return (messages || []).map(message => {
            if (!message?.Id) return message;
            const isRetrying = this._isRetryingMessage(message.Id);
            return message.isRetrying === isRetrying
                ? message
                : { ...message, isRetrying };
        });
    }

    _extractBroadcastId(record) {
        return String(
            record?.groupId
            || record?.Id
            || record?.groupId__c
            || ''
        ).trim() || null;
    }

    async _pollTimeline(version) {
        const threadId = this.selectedThreadId || null;
        const groupId = this.selectedBroadcast?.groupId || null;
        const pollCursor = this.pollCursor;
        if (!threadId || !groupId) return;
        try {
            const response = await pollBroadcastMessages({
                threadId,
                cursor: pollCursor
            });
            if (!this._isActiveTimelineContext(version, threadId, groupId)) return;

            const normalizedMessages = await this._enrichBroadcastMessages(
                response?.messages,
                version,
                threadId,
                this.selectedBroadcast?.canPublish === true
            );
            if (!this._isActiveTimelineContext(version, threadId, groupId)) return;

            const relevantDeltaMessages = this._collectRelevantPollDeltaMessages(
                this.messages,
                normalizedMessages
            );
            const previousMessageCount = this.messages.length;
            const mergedMessages = this._mergeMessages(this.messages, normalizedMessages);
            this.messages = mergedMessages;
            this.messageCount += Math.max(0, mergedMessages.length - previousMessageCount);
            this.pollCursor = response?.nextCursor || this._buildPollCursor(mergedMessages);
            this.timelineErrorMessage = '';

            if (!this._isActiveTimelineContext(version, threadId, groupId)) return;
            if (!this._hasAppliedRelevantPollDelta(mergedMessages, relevantDeltaMessages)) return;

            const markedAsRead = await this._markSelectedBroadcastAsRead(version, threadId);
            if (!markedAsRead) return;
            if (!this._isActiveTimelineContext(version, threadId, groupId)) return;

            await this._loadList({
                version,
                reset: true,
                preserveExistingItems: false,
                preserveErrorMessage: true,
                silent: true
            });
        } catch (error) {
            if (!this._isRequestValid(version)) return;
            await this._handleTimelineError(error, { fallbackToList: false });
        }
    }

    async _markSelectedBroadcastAsRead(version, threadId) {
        if (!threadId) return false;
        if (this._broadcastReadInFlightThreadId === threadId) return false;
        this._broadcastReadInFlightThreadId = threadId;
        try {
            await markBroadcastAsRead({ threadId });
            if (!this._isRequestValid(version)) return false;
            this.dispatchEvent(new CustomEvent('broadcastunreadchange', {
                detail: {
                    groupId: this.selectedBroadcast?.groupId || null,
                    threadId
                }
            }));
            return true;
        } catch (error) {
            if (!this._isRequestValid(version)) return false;
            await this._handleTimelineError(error, { fallbackToList: false });
            return false;
        } finally {
            if (this._broadcastReadInFlightThreadId === threadId) {
                this._broadcastReadInFlightThreadId = null;
            }
        }
    }

    async _handleOpenError(error) {
        const message = this._normalizeError(error);
        if (this._isAccessLostMessage(message)) {
            await this._handleAccessLoss(message);
            return;
        }
        if (this._isUnavailableMessage(message)) {
            this._resetTimelineState();
            this.view = VIEW_LIST;
            this.listErrorMessage = GENERIC_UNAVAILABLE_MESSAGE;
            return;
        }
        this._resetTimelineState();
        this.view = VIEW_LIST;
        this.listErrorMessage = message || GENERIC_TIMELINE_ERROR_MESSAGE;
    }

    async _handleTimelineError(error, { fallbackToList }) {
        const message = this._normalizeError(error);
        if (this._isAccessLostMessage(message)) {
            await this._handleAccessLoss(message);
            return;
        }
        if (this._isUnavailableMessage(message)) {
            this._resetTimelineState();
            this.view = VIEW_LIST;
            this.listErrorMessage = GENERIC_UNAVAILABLE_MESSAGE;
            return;
        }
        if (fallbackToList) {
            this._resetTimelineState();
            this.view = VIEW_LIST;
            this.listErrorMessage = message || GENERIC_TIMELINE_ERROR_MESSAGE;
            return;
        }
        this.timelineErrorMessage = message || GENERIC_TIMELINE_ERROR_MESSAGE;
    }

    async _handleSearchError(error) {
        const message = this._normalizeError(error);
        if (this._isAccessLostMessage(message)) {
            await this._handleAccessLoss(message);
            return;
        }
        if (this._isUnavailableMessage(message)) {
            this._resetTimelineState();
            this.view = VIEW_LIST;
            this.listErrorMessage = GENERIC_UNAVAILABLE_MESSAGE;
            return;
        }
        this.searchResults = [];
        this.searchErrorMessage = message || GENERIC_SEARCH_ERROR_MESSAGE;
    }

    async _handleAccessLoss(message) {
        const version = this._invalidateRequests();
        this._resetTimelineState();
        this.view = VIEW_LIST;
        this.listErrorMessage = message || ACCESS_DENIED_MESSAGE;
        await this._loadList({
            version,
            reset: true,
            preserveExistingItems: false,
            preserveErrorMessage: true
        });
    }

    _resetBroadcastState({ preserveItems }) {
        this.view = VIEW_LIST;
        this.items = preserveItems ? this.items : [];
        this.nextCursor = preserveItems ? this.nextCursor : null;
        this.listErrorMessage = '';
        this._resetTimelineState();
    }

    _resetTimelineState() {
        this._invalidateImagePreviewRequest({ notifyHost: true });
        this.selectedBroadcast = null;
        this.selectedThreadId = null;
        this.messages = [];
        this.messageCount = 0;
        this.messageOffset = 0;
        this.hasMoreMessagesState = false;
        this.pollCursor = null;
        this.searchKeyword = '';
        this.searchResults = [];
        this.timelineErrorMessage = '';
        this.searchErrorMessage = '';
        this.isLoadingTimeline = false;
        this.isLoadingMoreMessages = false;
        this.isSearching = false;
        this.isSearchOpen = false;
        this.composerMode = 'publish';
        this.editingMessage = null;
        this.editingAttachmentDraft = null;
        this.isDetailsModalOpen = false;
        this.detailsModalMode = 'edit';
        this._resetInlineImageCache();
        this._shouldScrollToBottom = false;
        this._shouldScrollCompactTimelineToBottom = false;
        this._shouldScrollAfterPublish = false;
        this._pendingInitialExpandRequest = null;
    }

    async _navigateToMessage(messageId) {
        if (!messageId || !this.selectedThreadId) return;

        const version = this.requestVersion;
        const threadId = this.selectedThreadId;
        const canManageBroadcast = this.selectedBroadcast?.canPublish === true;
        const isMessageAlreadyLoaded = (this.messages || []).some(message => message?.Id === messageId);

        this.handleClearSearch();
        this.timelineErrorMessage = '';

        if (isMessageAlreadyLoaded) {
            this._scrollTimelineToMessage(messageId);
            return;
        }

        this.isLoadingMoreMessages = true;
        try {
            const position = await getBroadcastMessageOffset({ threadId, messageId });
            if (!this._isRequestValid(version)) return;

            const offset = Math.max(0, Number(position || 0) - Math.floor(this._messagePageSize / 2));
            const rawMessages = await getBroadcastMessages({
                threadId,
                pageSize: this._messagePageSize,
                offsetVal: offset
            });
            if (!this._isRequestValid(version)) return;

            const normalizedMessages = await this._enrichBroadcastMessages(
                rawMessages,
                version,
                threadId,
                canManageBroadcast
            );
            if (!this._isRequestValid(version)) return;

            this.messages = normalizedMessages;
            this.messageOffset = offset;
            this.hasMoreMessagesState = offset > 0;
            this.pollCursor = this._buildPollCursor(normalizedMessages);
            this._scrollTimelineToMessage(messageId);
        } catch (error) {
            if (!this._isRequestValid(version)) return;
            await this._handleTimelineError(error, { fallbackToList: false });
        } finally {
            if (this._isRequestValid(version)) {
                this.isLoadingMoreMessages = false;
            }
        }
    }

    _scrollTimelineToMessage(messageId) {
        const timeline = this.template.querySelector('c-communicator-broadcast-timeline');
        if (!timeline || !messageId) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const targetTimeline = this.template.querySelector('c-communicator-broadcast-timeline');
            if (!targetTimeline) return;
            targetTimeline.expandMessage(messageId);
            targetTimeline.scrollToMessage(messageId);
        }, 100);
    }

    _requestWorkspaceScrollToBottom() {
        this._shouldScrollToBottom = true;
    }

    _requestScrollAfterPublish() {
        this._shouldScrollAfterPublish = true;
    }

    _requestInitialBroadcastScroll() {
        if (this._pendingInitialExpandRequest?.messageId) {
            this._pendingInitialExpandRequest = {
                ...this._pendingInitialExpandRequest,
                scrollVariant: this._variant
            };
            return;
        }

        if (this._variant === VARIANT_COMPACT) {
            this._shouldScrollCompactTimelineToBottom = true;
            return;
        }

        this._requestWorkspaceScrollToBottom();
    }

    _prepareInitialExpandMessage(messages) {
        const orderedMessages = Array.isArray(messages) ? messages : [];
        const lastMessage = orderedMessages.length ? orderedMessages[orderedMessages.length - 1] : null;
        this._pendingInitialExpandRequest = lastMessage?.Id
            ? {
                requestVersion: this.requestVersion,
                threadId: this.selectedThreadId || null,
                groupId: this.selectedBroadcast?.groupId || null,
                messageId: lastMessage.Id,
                scrollVariant: null
            }
            : null;
    }

    _invalidateRequests() {
        this.requestVersion += 1;
        this.refreshInFlight = false;
        this._searchSequence += 1;
        return this.requestVersion;
    }

    _isRequestValid(version) {
        return this._isConnected && version === this.requestVersion;
    }

    _isActiveTimelineContext(version, threadId, groupId) {
        return this._isRequestValid(version)
            && this.view === VIEW_TIMELINE
            && (this.selectedThreadId || null) === (threadId || null)
            && (this.selectedBroadcast?.groupId || null) === (groupId || null);
    }

    _isPendingInitialExpandRequestCurrent(pendingRequest, timeline) {
        if (!pendingRequest?.messageId || !pendingRequest?.threadId) return false;
        if (!this._isRequestValid(pendingRequest.requestVersion)) return false;
        if ((this.selectedThreadId || null) !== pendingRequest.threadId) return false;
        if ((this.selectedBroadcast?.groupId || null) !== (pendingRequest.groupId || null)) return false;
        if (!(this.messages || []).some(message => message?.Id === pendingRequest.messageId)) return false;
        if (!timeline || typeof timeline.expandMessage !== 'function') return false;
        if ((timeline.broadcast?.groupId || null) !== (pendingRequest.groupId || null)) return false;
        return Array.isArray(timeline.messages)
            && timeline.messages.some(message => message?.Id === pendingRequest.messageId);
    }

    _notifyViewChangeIfNeeded() {
        if (this._lastDispatchedView === this.view) return;
        this._lastDispatchedView = this.view;
        this.dispatchEvent(new CustomEvent('broadcastviewchange', {
            detail: {
                view: this.view,
                isTimelineView: this.view === VIEW_TIMELINE
            }
        }));
    }

    _normalizeBroadcastItems(items) {
        return (items || []).map(item => this._normalizeBroadcastItem(item)).filter(Boolean);
    }

    _normalizeBroadcastItem(item) {
        if (!item?.groupId) return null;
        const unreadCount = Math.max(0, Number(item.unreadCount) || 0);
        return {
            groupId: item.groupId,
            groupName: item.groupName || 'Comunicado sem titulo',
            description: item.description || '',
            createdByUserId: item.createdByUserId || null,
            createdByUserName: item.createdByUserName || '',
            createdByUserPhotoUrl: item.createdByUserPhotoUrl || '',
            creatorInitial: this._buildInitial(item.createdByUserName || item.groupName || 'C'),
            threadId: item.threadId || null,
            broadcastLastActivityAt: item.broadcastLastActivityAt || item.lastMessageAt || null,
            lastMessageAt: item.lastMessageAt || item.broadcastLastActivityAt || null,
            unreadCount,
            canPublish: item.canPublish === true
        };
    }

    _mergeBroadcastItems(baseItems, incomingItems) {
        const orderedItems = [];
        const itemsByGroupId = new Map();

        (baseItems || []).forEach(item => {
            if (!item?.groupId || itemsByGroupId.has(item.groupId)) return;
            itemsByGroupId.set(item.groupId, item);
            orderedItems.push(item.groupId);
        });

        (incomingItems || []).forEach(item => {
            if (!item?.groupId) return;
            if (!itemsByGroupId.has(item.groupId)) {
                orderedItems.push(item.groupId);
            }
            itemsByGroupId.set(item.groupId, item);
        });

        return orderedItems
            .filter(groupId => itemsByGroupId.has(groupId))
            .map(groupId => itemsByGroupId.get(groupId));
    }

    _normalizeMessages(messages) {
        return (messages || [])
            .map(message => this._normalizeMessage(message))
            .filter(Boolean)
            .sort((left, right) => this._compareMessages(left, right));
    }

    _normalizeMessage(message) {
        if (!message?.Id) return null;
        const senderName = message?.senderName
            || message?.Sender__r?.Name
            || message?.CreatedBy?.Name
            || (message?.isSystemMessage ? 'Sistema' : 'Usuario');
        const senderPhotoUrl = message?.senderPhotoUrl
            || message?.Sender__r?.SmallPhotoUrl
            || message?.CreatedBy?.SmallPhotoUrl
            || '';

        return {
            Id: message.Id,
            threadId: message.threadId || this.selectedThreadId || null,
            subject: message.subject || '',
            body: message.body || '',
            searchBody: message.searchBody || '',
            sentAt: message.sentAt || null,
            editedAt: message.editedAt || null,
            SystemModstamp: message.SystemModstamp || message.sentAt || null,
            isSystemMessage: message.isSystemMessage === true,
            senderId: message.senderId || null,
            senderName,
            senderPhotoUrl,
            senderInitial: this._buildInitial(senderName),
            status: message.status || '',
            distributionError: message.broadcastDistributionError || '',
            hasAttachment: message.hasAttachment === true,
            attachments: [],
            isRetrying: this._isRetryingMessage(message.Id),
            showEditAction: message.showEditAction === true,
            canEdit: message.canEdit === true,
            editDeadline: message.editDeadline || null,
            editBlockedReason: message.editBlockedReason || '',
            canRetry: message.canRetry === true
        };
    }

    _mergeMessages(baseMessages, incomingMessages) {
        const merged = new Map();
        (baseMessages || []).forEach(message => {
            if (!message?.Id) return;
            merged.set(message.Id, message);
        });
        (incomingMessages || []).forEach(message => {
            if (!message?.Id) return;
            merged.set(message.Id, message);
        });
        return Array.from(merged.values()).sort((left, right) => this._compareMessages(left, right));
    }

    _collectRelevantPollDeltaMessages(currentMessages, incomingMessages) {
        if (!Array.isArray(incomingMessages) || !incomingMessages.length) return [];
        const currentById = new Map(
            (currentMessages || [])
                .filter(message => !!message?.Id)
                .map(message => [message.Id, message])
        );

        return incomingMessages.filter(message => {
            if (!message?.Id) return false;
            const currentMessage = currentById.get(message.Id);
            if (!currentMessage) return true;
            return this._didRelevantBroadcastMessageContentChange(currentMessage, message);
        });
    }

    _hasAppliedRelevantPollDelta(mergedMessages, relevantMessages) {
        if (!Array.isArray(relevantMessages) || !relevantMessages.length) return false;
        const mergedById = new Map(
            (mergedMessages || [])
                .filter(message => !!message?.Id)
                .map(message => [message.Id, message])
        );

        return relevantMessages.every(message => {
            const mergedMessage = mergedById.get(message.Id);
            if (!mergedMessage) return false;
            return String(mergedMessage.subject || '') === String(message.subject || '')
                && String(mergedMessage.body || '') === String(message.body || '');
        });
    }

    _didRelevantBroadcastMessageContentChange(currentMessage, nextMessage) {
        return String(currentMessage?.subject || '') !== String(nextMessage?.subject || '')
            || String(currentMessage?.body || '') !== String(nextMessage?.body || '');
    }

    _compareMessages(left, right) {
        const leftTime = Date.parse(left?.sentAt || 0);
        const rightTime = Date.parse(right?.sentAt || 0);
        if (leftTime !== rightTime) return leftTime - rightTime;
        return String(left?.Id || '').localeCompare(String(right?.Id || ''));
    }

    _buildPollCursor(messages) {
        const list = messages || [];
        const lastMessage = list.length ? list[list.length - 1] : null;
        if (!lastMessage?.SystemModstamp || !lastMessage?.Id) return null;
        return JSON.stringify({
            timestampValue: lastMessage.SystemModstamp,
            recordId: lastMessage.Id
        });
    }

    _buildInitial(value) {
        return String(value || '')
            .trim()
            .charAt(0)
            .toUpperCase() || 'C';
    }

    _findAttachmentMetadata(messageId, contentDocumentId) {
        const normalizedMessageId = String(messageId || '').trim();
        const normalizedDocumentId = String(contentDocumentId || '').trim();
        if (!normalizedDocumentId) return null;

        const allMessages = [
            ...(this.messages || []),
            ...(this.searchResults || [])
        ];

        for (const message of allMessages) {
            if (normalizedMessageId && message?.Id !== normalizedMessageId) continue;
            const match = (message?.attachments || []).find(
                attachment => attachment?.contentDocumentId === normalizedDocumentId
            );
            if (match) return match;
        }

        for (const message of allMessages) {
            const match = (message?.attachments || []).find(
                attachment => attachment?.contentDocumentId === normalizedDocumentId
            );
            if (match) return match;
        }

        return null;
    }

    @api
    notifyImagePreviewClosed() {
        this._invalidateImagePreviewRequest();
    }

    _beginImagePreviewRequest() {
        this._imagePreviewRequestToken += 1;
        this._hasPendingImagePreview = true;
        return this._imagePreviewRequestToken;
    }

    _dispatchImagePreviewOpen({ src, fileName }) {
        const normalizedFileName = String(fileName || '').trim() || 'Imagem anexada';
        const normalizedSrc = String(src || '').trim();
        if (!normalizedSrc) return;
        // The host shell listens directly on <c-communicator-broadcast-workspace>,
        // so bubbles/composed would only widen the event scope without benefit.
        this.dispatchEvent(new CustomEvent('broadcastimagepreviewopen', {
            detail: {
                src: normalizedSrc,
                fileName: normalizedFileName,
                alternativeText: `Imagem anexada: ${normalizedFileName}`
            }
        }));
    }

    _dispatchImagePreviewClose() {
        this.dispatchEvent(new CustomEvent('broadcastimagepreviewclose'));
    }

    _invalidateImagePreviewRequest({ notifyHost = false } = {}) {
        const shouldNotifyHost = notifyHost && this._hasPendingImagePreview;
        this._imagePreviewRequestToken += 1;
        this._hasPendingImagePreview = false;
        if (shouldNotifyHost) {
            this._dispatchImagePreviewClose();
        }
    }

    _handleImagePreviewError(message, requestToken) {
        if (!this._isImagePreviewRequestCurrent(requestToken)) return;
        this._invalidateImagePreviewRequest({ notifyHost: true });
        this.timelineErrorMessage = String(message || IMAGE_PREVIEW_ERROR_MESSAGE).trim()
            || IMAGE_PREVIEW_ERROR_MESSAGE;
    }

    _isImagePreviewRequestCurrent(requestToken) {
        return this._hasPendingImagePreview === true
            && requestToken === this._imagePreviewRequestToken;
    }

    _buildEditingAttachmentDraft(message) {
        const seen = new Set();
        const originalAttachments = (message?.attachments || [])
            .map(attachment => {
                const documentId = String(attachment?.contentDocumentId || attachment?.documentId || '').trim();
                if (!documentId || seen.has(documentId)) return null;
                seen.add(documentId);
                return {
                    localId: `broadcast-edit-original-${documentId}`,
                    documentId,
                    fileName: String(attachment?.fileName || '').trim() || 'arquivo',
                    fileExtension: String(attachment?.fileExtension || '').trim(),
                    origin: 'original'
                };
            })
            .filter(Boolean);
        return this._buildAttachmentDraft({
            originalAttachments,
            newAttachments: [],
            removedOriginalAttachmentIds: []
        });
    }

    _setEditingAttachmentDraft(draft) {
        this.editingAttachmentDraft = this._buildAttachmentDraft(draft);
    }

    _buildAttachmentDraft(draft) {
        const removed = new Set(
            (draft?.removedOriginalAttachmentIds || [])
                .map(documentId => String(documentId || '').trim())
                .filter(Boolean)
        );
        const originalAttachments = this._dedupeDraftAttachments(
            draft?.originalAttachments,
            'original'
        );
        const originalIds = new Set(originalAttachments.map(file => file.documentId));
        const newAttachments = this._dedupeDraftAttachments(
            draft?.newAttachments,
            'new',
            originalIds
        );
        const visibleAttachments = [
            ...originalAttachments.filter(file => !removed.has(file.documentId)),
            ...newAttachments
        ];
        return {
            originalAttachments,
            newAttachments,
            removedOriginalAttachmentIds: Array.from(removed).filter(documentId => originalIds.has(documentId)),
            visibleAttachments
        };
    }

    _dedupeDraftAttachments(files, origin, blockedIds = new Set()) {
        const seen = new Set();
        return (files || [])
            .map(file => {
                const documentId = String(file?.documentId || file?.contentDocumentId || '').trim();
                if (!documentId || seen.has(documentId) || blockedIds.has(documentId)) return null;
                seen.add(documentId);
                return {
                    localId: file?.localId || `broadcast-edit-${origin}-${documentId}`,
                    documentId,
                    fileName: String(file?.fileName || '').trim() || 'arquivo',
                    fileExtension: String(file?.fileExtension || '').trim(),
                    origin
                };
            })
            .filter(Boolean);
    }

    async _deleteTemporaryAttachments(files) {
        const documentIds = Array.from(new Set(
            (files || [])
                .map(file => String(file?.documentId || '').trim())
                .filter(Boolean)
        ));
        for (const documentId of documentIds) {
            await deleteRecord(documentId);
        }
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _normalizeError(error) {
        return String(
            error?.body?.message
            || error?.message
            || error?.statusText
            || ''
        ).trim();
    }

    _isAccessLostMessage(message) {
        return message === ACCESS_DENIED_MESSAGE;
    }

    _isUnavailableMessage(message) {
        return message === BROADCAST_NOT_FOUND_MESSAGE || message === BROADCAST_THREAD_NOT_FOUND_MESSAGE;
    }

    get isListView() {
        return this.view === VIEW_LIST;
    }

    get isTimelineView() {
        return this.view === VIEW_TIMELINE;
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get hasMoreListItems() {
        return !!this.nextCursor;
    }

    get timelineMessages() {
        return this.isSearchActive ? this.searchResults : this.messages;
    }

    get isSearchActive() {
        return this.searchKeyword.trim().length >= MIN_SEARCH_KEYWORD_LEN || this.isSearching;
    }

    get hasTimelineMessages() {
        return this.timelineMessages.length > 0;
    }

    get hasMoreMessages() {
        return !this.isSearchActive && this.hasMoreMessagesState;
    }

    get hasThread() {
        return !!this.selectedThreadId;
    }

    get canManageBroadcast() {
        return this.selectedBroadcast?.canPublish === true;
    }

    get showComposer() {
        return !!this.selectedBroadcast && this.canManageBroadcast;
    }

    get detailsBroadcastId() {
        return this.selectedBroadcast?.groupId || null;
    }

    get showDetailsModal() {
        return this._variant === VARIANT_EXPANDED && this.isDetailsModalOpen;
    }

    get workspaceStyle() {
        return this._variant === VARIANT_COMPACT
            ? '--comm-broadcast-workspace-gap: 0.5rem;'
            : '--comm-broadcast-workspace-gap: 0.75rem;';
    }

    get timelineStyle() {
        if (this._variant === VARIANT_COMPACT && this._isCommunityContext) {
            return [
                '--comm-broadcast-timeline-padding: 0.45rem 0.55rem 0.3rem',
                '--comm-broadcast-timeline-header-gap: 0.35rem',
                '--comm-broadcast-timeline-header-margin-bottom: 0.35rem',
                '--comm-broadcast-timeline-back-font-size: 0.74rem',
                '--comm-broadcast-timeline-hero-padding: 0.5rem 0.65rem',
                '--comm-broadcast-timeline-hero-gap: 0.5rem',
                '--comm-broadcast-timeline-hero-border-radius: 0.75rem',
                '--comm-broadcast-timeline-avatar-size: 1.75rem',
                '--comm-broadcast-timeline-title-font-size: 0.86rem',
                '--comm-broadcast-timeline-meta-font-size: 0.68rem',
                '--comm-broadcast-timeline-description-font-size: 0.7rem',
                '--comm-broadcast-timeline-description-margin: 0.08rem 0 0',
                '--comm-broadcast-timeline-search-min-height: 2rem',
                '--comm-broadcast-timeline-search-padding: 0.25rem 0.55rem',
                '--comm-broadcast-timeline-messages-gap: 0.45rem',
                '--comm-broadcast-timeline-photo-size: 1.55rem',
                '--comm-broadcast-timeline-message-gap: 0.45rem',
                '--comm-broadcast-timeline-message-content-gap: 0.22rem',
                '--comm-broadcast-timeline-sender-font-size: 0.72rem',
                '--comm-broadcast-timeline-sent-at-font-size: 0.62rem',
                '--comm-broadcast-timeline-bubble-padding: 0.42rem 0.58rem',
                '--comm-broadcast-timeline-bubble-font-size: 0.74rem',
                '--comm-broadcast-timeline-bubble-line-height: 1.32'
            ].join('; ') + ';';
        }

        return '';
    }

    get composerStyle() {
        if (this._variant === VARIANT_COMPACT) {
            if (this._isCommunityContext) {
                return [
                    '--comm-broadcast-composer-margin-top: 0.15rem',
                    '--comm-broadcast-composer-padding: 0.38rem 0.55rem',
                    '--comm-broadcast-composer-font-size: 0.74rem',
                    '--comm-broadcast-composer-field-gap: 0.15rem',
                    '--comm-broadcast-composer-field-margin-bottom: 0.24rem',
                    '--comm-broadcast-composer-label-font-size: 0.68rem',
                    '--comm-broadcast-composer-input-min-height: 1.95rem',
                    '--comm-broadcast-composer-input-padding: 0.28rem 0.48rem',
                    '--comm-broadcast-composer-textarea-height: 2.55rem',
                    '--comm-broadcast-composer-textarea-min-height: 2.55rem',
                    '--comm-broadcast-composer-textarea-padding: 0.34rem 0.48rem',
                    '--comm-broadcast-composer-control-line-height: 1.25',
                    '--comm-broadcast-composer-meta-font-size: 0.61rem',
                    '--comm-broadcast-composer-meta-line-height: 1.15',
                    '--comm-broadcast-composer-actions-gap: 0.32rem',
                    '--comm-broadcast-composer-actions-margin-top: 0.32rem',
                    '--comm-broadcast-composer-button-font-size: 0.68rem',
                    '--comm-broadcast-composer-button-padding: 0.34rem 0.7rem',
                    '--comm-broadcast-composer-upload-min-height: 1.75rem',
                    '--comm-broadcast-composer-upload-padding: 0.3rem 0.62rem'
                ].join('; ') + ';';
            }

            return [
                '--comm-broadcast-composer-margin-top: 0.45rem',
                '--comm-broadcast-composer-padding: 0.75rem',
                '--comm-broadcast-composer-header-margin: 0.6rem',
                '--comm-broadcast-composer-textarea-min-height: 5.25rem',
                '--comm-broadcast-composer-textarea-padding: 0.7rem',
                '--comm-broadcast-composer-actions-gap: 0.55rem',
                '--comm-broadcast-composer-actions-margin-top: 0.65rem'
            ].join('; ') + ';';
        }

        return [
            '--comm-broadcast-composer-margin-top: 0.85rem',
            '--comm-broadcast-composer-padding: 1rem',
            '--comm-broadcast-composer-header-margin: 0.75rem',
            '--comm-broadcast-composer-textarea-min-height: 6.25rem',
            '--comm-broadcast-composer-textarea-padding: 0.8rem',
            '--comm-broadcast-composer-actions-gap: 0.65rem',
            '--comm-broadcast-composer-actions-margin-top: 0.8rem'
        ].join('; ') + ';';
    }
}