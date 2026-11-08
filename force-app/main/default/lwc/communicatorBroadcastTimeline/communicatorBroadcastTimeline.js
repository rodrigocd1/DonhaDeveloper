import { LightningElement, api } from 'lwc';

const VARIANT_EXPANDED = 'expanded';
const DEBOUNCE_MS = 350;
const MIN_SEARCH_KEYWORD_LEN = 3;
const EMPTY_BROADCAST_MESSAGE = 'Nenhuma publicação neste grupo de comunicados.';
const EMPTY_THREAD_MESSAGE = 'Nenhuma mensagem encontrada neste comunicado.';
const EMPTY_SEARCH_MESSAGE = 'Nenhuma mensagem encontrada para esta busca.';
const LEGACY_SUBJECT_LABEL = 'Sem assunto';
const SEARCH_SNIPPET_RADIUS = 80;
const INLINE_IMAGE_EXTENSIONS = new Set(['jpeg', 'jpg', 'png']);
const BODY_LINK_PROTOCOLS = new Set(['http:', 'https:']);
const INLINE_IMAGE_STATUS_NOT_LOADED = 'notLoaded';
const INLINE_IMAGE_STATUS_LOADING = 'loading';
const INLINE_IMAGE_STATUS_LOADED = 'loaded';
const INLINE_IMAGE_STATUS_ERROR = 'error';
const MESSAGE_STATUS_QUEUED = 'Queued';
const MESSAGE_STATUS_PROCESSING = 'Processing';
const MESSAGE_STATUS_FAILED = 'Failed';
const STATUS_LABEL_BY_VALUE = {
    [MESSAGE_STATUS_QUEUED]: 'Distribuicao na fila',
    [MESSAGE_STATUS_PROCESSING]: 'Distribuicao em andamento',
    [MESSAGE_STATUS_FAILED]: 'Falha na distribuição'
};

export default class CommunicatorBroadcastTimeline extends LightningElement {
    _searchKeyword = '';
    _pendingPrependScrollState = null;
    _activeHighlightTimeout = null;
    _highlightedElement = null;
    _searchDebounceTimer = null;
    _isSearchOpen = false;
    _editingMessage = null;
    _shouldScrollToBottom = false;
    _messages = [];
    _expandedMessageIds = [];
    _lastInlineImageRequestKey = '';

    @api variant;
    @api broadcast;
    @api isSearchActive = false;
    @api isSearching = false;
    @api isLoading = false;
    @api isLoadingMore = false;
    @api hasMoreMessages = false;
    @api errorMessage = '';
    @api searchErrorMessage = '';
    @api canManageBroadcast = false;
    @api hasThread = false;

    @api
    get messages() {
        return this._messages;
    }

    set messages(value) {
        this._messages = Array.isArray(value) ? value : [];
        this._reconcileExpandedMessages();
    }

    @api
    get editingMessage() {
        return this._editingMessage;
    }

    set editingMessage(value) {
        this._editingMessage = value || null;
    }

    localSearchKeyword = '';

    @api
    get isSearchOpen() {
        return this._isSearchOpen;
    }

    set isSearchOpen(value) {
        const next = value === true;
        if (!next && this._isSearchOpen) {
            this._clearSearchDebounceTimer();
        }
        this._isSearchOpen = next;
    }

    @api
    get searchKeyword() {
        return this._searchKeyword;
    }

    set searchKeyword(value) {
        this._searchKeyword = String(value || '');
        this.localSearchKeyword = this._searchKeyword;
    }

    renderedCallback() {
        this._renderSearchPreviews();
        this._requestVisibleInlineImages();

        if (this._pendingPrependScrollState) {
            const container = this.template.querySelector('.comm-broadcast-timeline__body');
            const state = this._pendingPrependScrollState;
            this._pendingPrependScrollState = null;
            if (container) {
                const scrollHeight = container.scrollHeight || 0;
                const heightDelta = scrollHeight - state.scrollHeight;
                container.scrollTop = state.scrollTop + Math.max(0, heightDelta);
            }
        }

        if (this._shouldScrollToBottom) {
            const bottom = this.template.querySelector('.comm-broadcast-timeline__bottom');
            if (bottom) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    const target = this.template.querySelector('.comm-broadcast-timeline__bottom');
                    if (target) {
                        target.scrollIntoView({ behavior: 'smooth', block: 'end' });
                    }
                }, 0);
                this._shouldScrollToBottom = false;
            }
        }
    }

    disconnectedCallback() {
        this._clearSearchDebounceTimer();
        if (this._activeHighlightTimeout) {
            clearTimeout(this._activeHighlightTimeout);
            this._activeHighlightTimeout = null;
        }
        this._clearHighlight();
    }

    @api
    capturePrependScrollState() {
        const container = this.template.querySelector('.comm-broadcast-timeline__body');
        if (!container) {
            this._pendingPrependScrollState = null;
            return;
        }
        this._pendingPrependScrollState = {
            scrollTop: container.scrollTop || 0,
            scrollHeight: container.scrollHeight || 0
        };
    }

    @api
    scrollToBottom() {
        const bottom = this.template.querySelector('.comm-broadcast-timeline__bottom');
        if (!bottom) return;
        bottom.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }

    @api
    scrollToTop() {
        const body = this.template.querySelector('.comm-broadcast-timeline__body');
        if (!body) return;
        body.scrollTop = 0;
    }

    @api
    requestScrollToBottom() {
        this._shouldScrollToBottom = true;
    }

    @api
    expandMessage(messageId) {
        const targetMessageId = String(messageId || '').trim();
        if (!targetMessageId) return;
        this._setMessageExpanded(targetMessageId, true);
        this._requestVisibleInlineImages();
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleOpenDetails() {
        if (this.variant !== VARIANT_EXPANDED || !this.canManageBroadcast || !this.hasBroadcast) return;
        this.dispatchEvent(new CustomEvent('details', {
            detail: {
                groupId: this.broadcast?.groupId || null,
                broadcast: this.broadcast
            }
        }));
    }

    handleEditMessage(event) {
        event.stopPropagation();
        const messageId = String(event.currentTarget?.dataset?.messageId || '').trim();
        if (!messageId) return;
        if (this._editingMessage?.Id && this._editingMessage.Id !== messageId) return;
        const message = (this._messages || []).find(item => item?.Id === messageId);
        if (!message) return;
        if (message.canEdit) {
            this.dispatchEvent(new CustomEvent('editmessage', {
                detail: { message }
            }));
            return;
        }
        if (String(message.editBlockedReason || '').trim()) {
            this.dispatchEvent(new CustomEvent('editblocked', {
                detail: { message: message.editBlockedReason }
            }));
        }
    }

    handleRetryMessage(event) {
        event.stopPropagation();
        const messageId = String(event.currentTarget?.dataset?.messageId || '').trim();
        if (!messageId) return;
        const message = (this._messages || []).find(item => item?.Id === messageId);
        if (!message || !message.canRetry) return;

        this.dispatchEvent(new CustomEvent('retrymessage', {
            detail: { messageId }
        }));
    }

    handleAttachmentClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const contentDocumentId = String(event.currentTarget?.dataset?.contentDocumentId || '').trim();
        const messageId = String(event.currentTarget?.dataset?.messageId || '').trim();
        const threadId = String(event.currentTarget?.dataset?.threadId || '').trim();
        if (!contentDocumentId) return;

        this.dispatchEvent(new CustomEvent('attachmentclick', {
            detail: {
                contentDocumentId,
                messageId,
                threadId: threadId || (this.broadcast?.threadId || null),
                fileExtension: String(event.currentTarget?.dataset?.fileExtension || '').trim(),
                fileName: String(event.currentTarget?.dataset?.fileName || '').trim()
            }
        }));
    }

    handleBodyLinkClick(event) {
        event.stopPropagation();
    }

    handleSubjectClick(event) {
        const messageId = String(event.currentTarget?.dataset?.messageId || '').trim();
        if (!messageId) return;

        event.stopPropagation();
        if (this.isSearchActive) {
            this.dispatchEvent(new CustomEvent('navigatemessage', {
                detail: { messageId }
            }));
            return;
        }

        const expanded = !this._isMessageExpanded(messageId);
        this._setMessageExpanded(messageId, expanded);
        if (expanded) {
            this._requestVisibleInlineImages();
        }
    }

    handleSearchInput(event) {
        this.localSearchKeyword = event.target.value;
        this._debounceSearch();
    }

    handleSearchKeyDown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            this._clearSearchInput();
            return;
        }
        if (event.key === 'Enter') {
            event.preventDefault();
            this._fireSearchNow();
        }
    }

    handleToggleSearch() {
        this.dispatchEvent(new CustomEvent('togglesearch', {
            bubbles: true,
            composed: true
        }));
    }

    handleLoadMoreMessages() {
        this.dispatchEvent(new CustomEvent('loadmoremessages'));
    }

    handleSearchResultClick(event) {
        if (!this.isSearchActive) return;
        if (this._editingMessage?.Id) return;
        const messageId = String(event.currentTarget?.dataset?.messageId || '').trim();
        if (!messageId) return;
        this.dispatchEvent(new CustomEvent('navigatemessage', {
            detail: { messageId }
        }));
    }

    _debounceSearch() {
        this._clearSearchDebounceTimer();
        const keyword = String(this.localSearchKeyword || '').trim();
        if (keyword.length < MIN_SEARCH_KEYWORD_LEN) {
            this._fireSearchNow();
            return;
        }

        this._searchDebounceTimer = setTimeout(() => {
            this._fireSearchNow();
        }, DEBOUNCE_MS);
    }

    _fireSearchNow() {
        this._clearSearchDebounceTimer();
        this.dispatchEvent(new CustomEvent('search', {
            detail: { keyword: this.localSearchKeyword }
        }));
    }

    _clearSearchInput() {
        this._clearSearchDebounceTimer();
        this.localSearchKeyword = '';
        this.dispatchEvent(new CustomEvent('clearsearch'));
    }

    _clearSearchDebounceTimer() {
        if (!this._searchDebounceTimer) return;
        clearTimeout(this._searchDebounceTimer);
        this._searchDebounceTimer = null;
    }

    @api
    scrollToMessage(messageId) {
        const targetMessageId = String(messageId || '').trim();
        if (!targetMessageId) return;
        this.expandMessage(targetMessageId);
        const element = this.template.querySelector(`[data-message-id="${targetMessageId}"]`);
        if (!element) return;
        element.scrollIntoView({ behavior: 'smooth', block: 'center' });
        this._applyHighlight(element);
    }

    get containerClass() {
        const classes = [
            'comm-broadcast-timeline',
            this.variant === VARIANT_EXPANDED
                ? 'comm-broadcast-timeline--expanded'
                : 'comm-broadcast-timeline--compact'
        ];
        if (this.isSearchActive) {
            classes.push('comm-broadcast-timeline--search-active');
        }
        if (this.showSearchForm) {
            classes.push('comm-broadcast-timeline--search-visible');
        }
        return classes.join(' ');
    }

    get hasMessages() {
        return this._messages.length > 0;
    }

    get renderedMessages() {
        const expandedIds = new Set(this._expandedMessageIds);
        const editingMessageId = this._editingMessage?.Id || null;
        return this._messages.map(message => {
            const subjectValue = String(message?.subject || '').trim();
            const isExpanded = expandedIds.has(message.Id);
            const isEditingMessage = editingMessageId && message?.Id === editingMessageId;
            const searchPreview = this.isSearchActive
                ? this._buildSearchPreview(message, this._searchKeyword)
                : null;
            return {
                ...message,
                hasBody: String(message?.body || '').trim().length > 0,
                bodyTokens: this._buildBodyTokens(message?.body),
                isExpanded,
                isEditingMessage,
                isSearchResult: !!searchPreview,
                attachments: this._buildRenderedAttachments(message),
                showEditAction: !!message?.showEditAction && !editingMessageId,
                showRetryAction: !!message?.canRetry && !editingMessageId,
                retryDisabled: message?.isRetrying === true,
                retryLabel: message?.isRetrying === true ? 'Reenfileirando...' : 'Reenfileirar',
                bubbleClass: isEditingMessage
                    ? 'comm-broadcast-timeline__bubble comm-broadcast-timeline__bubble--editing-target'
                    : 'comm-broadcast-timeline__bubble',
                statusLabel: this._resolveStatusLabel(message?.status),
                showStatusChip: this._shouldShowStatusChip(message?.status),
                statusClass: this._buildStatusClass(message?.status),
                showStatusError: String(message?.distributionError || '').trim().length > 0 && isExpanded,
                subjectButtonClass: isExpanded
                    ? 'comm-broadcast-timeline__subject comm-broadcast-timeline__subject--expanded'
                    : 'comm-broadcast-timeline__subject',
                subjectTextClass: searchPreview
                    ? 'comm-broadcast-timeline__subject-text comm-broadcast-timeline__subject-text--search'
                    : 'comm-broadcast-timeline__subject-text',
                subjectLabel: searchPreview?.text || subjectValue || LEGACY_SUBJECT_LABEL,
                searchPreviewHtml: searchPreview?.html || '',
                subjectToggleIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    get hasBroadcast() {
        return !!this.broadcast;
    }

    get showDetailsButton() {
        return this.variant === VARIANT_EXPANDED && this.canManageBroadcast && this.hasBroadcast;
    }

    get broadcastActivityAt() {
        return this.broadcast?.broadcastLastActivityAt
            || this.broadcast?.lastMessageAt
            || null;
    }

    get showSearchToggle() {
        return this.variant !== VARIANT_EXPANDED && this.hasThread;
    }

    get showSearchForm() {
        return this.hasThread && (this.variant === VARIANT_EXPANDED || this.isSearchOpen);
    }

    get searchToggleIconName() {
        return this.isSearchOpen ? 'utility:close' : 'utility:search';
    }

    get searchToggleLabel() {
        return this.isSearchOpen ? 'Fechar busca' : 'Abrir busca';
    }

    get emptyMessage() {
        if (this.isSearchActive) {
            return EMPTY_SEARCH_MESSAGE;
        }
        if (!this.hasThread) {
            return EMPTY_BROADCAST_MESSAGE;
        }
        return EMPTY_THREAD_MESSAGE;
    }

    _resolveStatusLabel(statusValue) {
        return STATUS_LABEL_BY_VALUE[String(statusValue || '').trim()] || '';
    }

    _shouldShowStatusChip(statusValue) {
        return !!this._resolveStatusLabel(statusValue);
    }

    _buildStatusClass(statusValue) {
        const normalizedStatus = String(statusValue || '').trim().toLowerCase();
        const classes = ['comm-broadcast-timeline__status-chip'];
        if (normalizedStatus === MESSAGE_STATUS_QUEUED.toLowerCase()) {
            classes.push('comm-broadcast-timeline__status-chip--queued');
        } else if (normalizedStatus === MESSAGE_STATUS_PROCESSING.toLowerCase()) {
            classes.push('comm-broadcast-timeline__status-chip--processing');
        } else if (normalizedStatus === MESSAGE_STATUS_FAILED.toLowerCase()) {
            classes.push('comm-broadcast-timeline__status-chip--failed');
        }
        return classes.join(' ');
    }

    _isMessageExpanded(messageId) {
        return this._expandedMessageIds.includes(messageId);
    }

    _setMessageExpanded(messageId, expanded) {
        const next = new Set(this._expandedMessageIds);
        if (expanded) {
            next.add(messageId);
        } else {
            next.delete(messageId);
        }
        this._expandedMessageIds = Array.from(next);
    }

    _buildRenderedAttachments(message) {
        return (message?.attachments || []).map(attachment => {
            const fileName = String(attachment?.fileName || '').trim() || 'arquivo';
            const fileExtension = String(attachment?.fileExtension || '').trim().toLowerCase();
            const inlineStatus = attachment?.inlineStatus || INLINE_IMAGE_STATUS_NOT_LOADED;
            const isInlineImage = attachment?.isInlineImage === true ||
                INLINE_IMAGE_EXTENSIONS.has(fileExtension);
            const isInlineLoaded = isInlineImage &&
                inlineStatus === INLINE_IMAGE_STATUS_LOADED &&
                !!attachment?.inlineSrc;
            const isInlineLoading = isInlineImage && inlineStatus === INLINE_IMAGE_STATUS_LOADING;
            const isInlineError = isInlineImage && inlineStatus === INLINE_IMAGE_STATUS_ERROR;
            return {
                ...attachment,
                fileName,
                fileExtension,
                isInlineImage,
                isInlineLoaded,
                isInlineLoading,
                isInlineError,
                attachmentRowClass: isInlineImage
                    ? 'comm-broadcast-timeline__attachment comm-broadcast-timeline__attachment--image'
                    : 'comm-broadcast-timeline__attachment',
                altText: `Imagem anexada: ${fileName}`,
                previewLabel: `Abrir imagem ${fileName}`,
                inlineErrorMessage: attachment?.inlineErrorMessage || 'Não foi possível carregar esta imagem.'
            };
        });
    }

    _requestVisibleInlineImages() {
        const requests = [];
        const expandedIds = new Set(this._expandedMessageIds);
        (this._messages || []).forEach(message => {
            if (!message?.Id || !expandedIds.has(message.Id)) return;
            (message.attachments || []).forEach(attachment => {
                if (!this._shouldRequestInlineImage(attachment)) return;
                requests.push({
                    contentDocumentId: attachment.contentDocumentId,
                    messageId: message.Id,
                    threadId: message.threadId || this.broadcast?.threadId || null,
                    fileName: attachment.fileName || 'arquivo',
                    fileExtension: attachment.fileExtension || ''
                });
            });
        });

        const requestKey = requests
            .map(item => `${item.messageId}:${item.contentDocumentId}`)
            .sort()
            .join('|');
        if (!requestKey) {
            this._lastInlineImageRequestKey = '';
            return;
        }
        if (requestKey === this._lastInlineImageRequestKey) return;
        this._lastInlineImageRequestKey = requestKey;
        this.dispatchEvent(new CustomEvent('loadinlineimages', {
            detail: { attachments: requests }
        }));
    }

    _shouldRequestInlineImage(attachment) {
        const contentDocumentId = String(attachment?.contentDocumentId || '').trim();
        const fileExtension = String(attachment?.fileExtension || '').trim().toLowerCase();
        if (!contentDocumentId || !INLINE_IMAGE_EXTENSIONS.has(fileExtension)) return false;
        const inlineStatus = attachment?.inlineStatus || INLINE_IMAGE_STATUS_NOT_LOADED;
        return inlineStatus === INLINE_IMAGE_STATUS_NOT_LOADED;
    }

    _reconcileExpandedMessages() {
        const validIds = new Set(this._messages.map(message => message?.Id).filter(messageId => !!messageId));
        this._expandedMessageIds = this._expandedMessageIds.filter(messageId => validIds.has(messageId));
    }

    _renderSearchPreviews() {
        if (!this.isSearchActive) return;
        this.renderedMessages.forEach(message => {
            if (!message.searchPreviewHtml) return;
            const element = this.template.querySelector(`[data-search-preview-id="${message.Id}"]`);
            if (!element) return;
            if (element.dataset.renderedPreview === message.searchPreviewHtml) return;
            // eslint-disable-next-line @lwc/lwc/no-inner-html
            element.innerHTML = message.searchPreviewHtml;
            element.dataset.renderedPreview = message.searchPreviewHtml;
        });
    }

    _buildSearchPreview(message, keyword) {
        const normalizedKeyword = String(keyword || '').trim();
        if (normalizedKeyword.length < MIN_SEARCH_KEYWORD_LEN) return null;

        const subject = String(message?.subject || '').trim();
        const body = String(message?.body || '').trim();
        const searchBody = String(message?.searchBody || '').trim();
        const bodyMatches = this._containsTerm(body, normalizedKeyword);
        const searchBodyMatches = this._containsTerm(searchBody, normalizedKeyword);
        const subjectMatches = this._containsTerm(subject, normalizedKeyword);

        if (bodyMatches) {
            const snippet = this._buildSnippet(body, normalizedKeyword);
            return {
                text: snippet,
                html: this._highlightKeyword(snippet, normalizedKeyword)
            };
        }

        if (searchBodyMatches && body) {
            const snippet = this._buildSnippet(body, normalizedKeyword);
            return {
                text: snippet,
                html: this._highlightKeyword(snippet, normalizedKeyword)
            };
        }

        const fallback = subjectMatches ? subject : (subject || body || LEGACY_SUBJECT_LABEL);
        return {
            text: fallback,
            html: this._highlightKeyword(fallback, normalizedKeyword)
        };
    }

    _containsTerm(text, keyword) {
        return String(text || '').toLocaleLowerCase()
            .includes(String(keyword || '').toLocaleLowerCase());
    }

    _buildSnippet(text, keyword) {
        const value = String(text || '').replace(/\s+/g, ' ').trim();
        const lowerValue = value.toLocaleLowerCase();
        const lowerKeyword = String(keyword || '').toLocaleLowerCase();
        const matchIndex = lowerValue.indexOf(lowerKeyword);
        if (matchIndex < 0) {
            return value.length > SEARCH_SNIPPET_RADIUS * 2
                ? `${value.slice(0, SEARCH_SNIPPET_RADIUS * 2).trim()}...`
                : value;
        }

        const start = Math.max(0, matchIndex - SEARCH_SNIPPET_RADIUS);
        const end = Math.min(value.length, matchIndex + lowerKeyword.length + SEARCH_SNIPPET_RADIUS);
        const prefix = start > 0 ? '...' : '';
        const suffix = end < value.length ? '...' : '';
        return `${prefix}${value.slice(start, end).trim()}${suffix}`;
    }

    _buildBodyTokens(bodyValue) {
        const body = String(bodyValue ?? '');
        const tokens = [];
        const urlRegex = /https?:\/\/[^\s]+/gi;
        let lastIndex = 0;
        let tokenIndex = 0;
        let match;

        while ((match = urlRegex.exec(body)) !== null) {
            const matchIndex = match.index;
            const rawUrl = match[0];
            if (matchIndex > lastIndex) {
                tokens.push(this._buildBodyTextToken(tokenIndex++, body.slice(lastIndex, matchIndex)));
            }

            const splitLink = this._splitTrailingLinkPunctuation(rawUrl);
            if (this._isSupportedBodyLink(splitLink.linkText)) {
                tokens.push(this._buildBodyLinkToken(tokenIndex++, splitLink.linkText));
                if (splitLink.trailingText) {
                    tokens.push(this._buildBodyTextToken(tokenIndex++, splitLink.trailingText));
                }
            } else {
                tokens.push(this._buildBodyTextToken(tokenIndex++, rawUrl));
            }
            lastIndex = matchIndex + rawUrl.length;
        }

        if (lastIndex < body.length) {
            tokens.push(this._buildBodyTextToken(tokenIndex++, body.slice(lastIndex)));
        }

        return tokens;
    }

    _buildBodyTextToken(index, text) {
        return {
            key: `body-token-${index}`,
            isLink: false,
            text
        };
    }

    _buildBodyLinkToken(index, href) {
        return {
            key: `body-token-${index}`,
            isLink: true,
            text: href,
            href
        };
    }

    _splitTrailingLinkPunctuation(rawUrl) {
        let linkText = String(rawUrl || '');
        let trailingText = '';
        const trailingCharacters = new Set(['.', ',', '!', '?', ';', ':', ')', ']', '}']);

        while (linkText.length > 0) {
            const candidate = linkText.charAt(linkText.length - 1);
            if (!trailingCharacters.has(candidate)) break;
            if (candidate === ')' && this._countCharacters(linkText, '(') >= this._countCharacters(linkText, ')')) {
                break;
            }
            if (candidate === ']' && this._countCharacters(linkText, '[') >= this._countCharacters(linkText, ']')) {
                break;
            }
            if (candidate === '}' && this._countCharacters(linkText, '{') >= this._countCharacters(linkText, '}')) {
                break;
            }
            trailingText = `${candidate}${trailingText}`;
            linkText = linkText.slice(0, -1);
        }

        return { linkText, trailingText };
    }

    _countCharacters(text, character) {
        return (String(text || '').match(new RegExp(`\\${character}`, 'g')) || []).length;
    }

    _isSupportedBodyLink(linkText) {
        if (!linkText) return false;
        try {
            const parsedUrl = new URL(linkText);
            return BODY_LINK_PROTOCOLS.has(parsedUrl.protocol);
        } catch (e) {
            return false;
        }
    }

    _highlightKeyword(text, keyword) {
        if (!text || !keyword) return this._escapeHtml(text);
        const escaped = this._escapeHtml(text);
        const escapedKeyword = String(keyword).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const regex = new RegExp(`(${escapedKeyword})`, 'gi');
        return escaped.replace(regex, '<mark class="comm-broadcast-timeline__search-highlight">$1</mark>');
    }

    _escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    _applyHighlight(element) {
        this._clearHighlight();
        element.classList.add('comm-broadcast-timeline__message--highlighted');
        this._highlightedElement = element;
        this._activeHighlightTimeout = setTimeout(() => {
            this._clearHighlight();
        }, 1800);
    }

    _clearHighlight() {
        if (this._highlightedElement) {
            this._highlightedElement.classList.remove('comm-broadcast-timeline__message--highlighted');
            this._highlightedElement = null;
        }
        if (this._activeHighlightTimeout) {
            clearTimeout(this._activeHighlightTimeout);
            this._activeHighlightTimeout = null;
        }
    }
}