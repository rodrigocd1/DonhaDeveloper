import { LightningElement, api } from 'lwc';
import getChatterHistoryPage from '@salesforce/apex/CommunicatorChatterHistoryService.getChatterHistoryPage';
import getChatterHistoryPageForFeedItem from '@salesforce/apex/CommunicatorChatterHistoryService.getChatterHistoryPageForFeedItem';
import searchChatterHistory from '@salesforce/apex/CommunicatorChatterHistoryService.searchChatterHistory';
import getAttachmentFile from '@salesforce/apex/CommunicatorChatterHistoryService.getAttachmentFile';
import getSettings from '@salesforce/apex/CommunicatorChatController.getSettings';
import { openAttachmentFromBase64 as openCommunicatorAttachmentFromBase64 } from 'c/communicatorAttachmentService';

const DEFAULT_ERROR_MESSAGE = 'Não foi possível carregar o Histórico Chatter.';
const DEFAULT_CHATTER_HISTORY_EMPTY_MESSAGE =
    'Esta oportunidade não possui Histórico Chatter elegível no conjunto atual.';
const MIN_SEARCH_TERM_LENGTH = 2;
const PAGING_DIRECTION_NEWER = 'newer';
export default class CommunicatorChatterHistory extends LightningElement {
    @api allowNavigation = false;
    @api openFilesInNewTab = false;
    @api embedded = false;
    @api hideToolbar = false;
    @api useExternalSearch = false;
    @api loadAllMessages = false;

    _opportunityId = null;
    _threadId = null;
    _externalSearchTerm = '';
    _isConnected = false;
    _contextVersion = 0;
    _configPromise = null;
    _hasLoadedConfig = false;
    _searchVersion = 0;
    _pendingScrollFeedItemId = null;
    _pendingScrollFeedCommentId = null;
    _pendingExpandComments = false;
    _pendingInitialScrollAnimation = false;
    _initialScrollAnimationFrame = null;
    _remainingPagesLoadPromise = null;
    _remainingPagesProgressWaiters = [];
    _isLoadingRemainingPages = false;

    posts = [];
    pageSize = null;
    searchTerm = '';
    searchResults = [];
    previousPageCursor = null;
    hasMore = false;
    isLoading = false;
    isLoadingMore = false;
    isSearching = false;
    searchCompleted = false;
    initialLoadCompleted = false;
    errorMessage = '';
    loadMoreErrorMessage = '';
    hasTruncatedComments = false;
    highlightedFeedItemId = null;
    highlightedFeedCommentId = null;
    chatterHistoryEmptyMessage = DEFAULT_CHATTER_HISTORY_EMPTY_MESSAGE;

    @api
    get opportunityId() {
        return this._opportunityId;
    }

    set opportunityId(value) {
        const normalizedValue = this.normalizeId(value);
        if (normalizedValue === this._opportunityId) {
            return;
        }

        this._opportunityId = normalizedValue;
        this._contextVersion += 1;
        this.resetState();

        if (this._isConnected && this.hasRequiredContext) {
            this.loadFirstPageForCurrentContext().catch(() => {});
        }
    }

    @api
    get threadId() {
        return this._threadId;
    }

    set threadId(value) {
        const normalizedValue = this.normalizeId(value);
        if (normalizedValue === this._threadId) {
            return;
        }

        this._threadId = normalizedValue;
        this._contextVersion += 1;
        this.resetState();

        if (this._isConnected && this.hasRequiredContext) {
            this.loadFirstPageForCurrentContext().catch(() => {});
        }
    }

    @api
    get externalSearchTerm() {
        return this._externalSearchTerm;
    }

    set externalSearchTerm(value) {
        const normalizedValue = String(value || '');
        if (normalizedValue === this._externalSearchTerm) {
            return;
        }

        this._externalSearchTerm = normalizedValue;
        if (this.useExternalSearch && this._isConnected) {
            this.performSearchForCurrentState().catch(() => {});
        }
    }

    connectedCallback() {
        this._isConnected = true;
        this.loadFirstPageForCurrentContext().catch(() => {});
    }

    disconnectedCallback() {
        this._isConnected = false;
        this._contextVersion += 1;
        this._searchVersion += 1;
        this.cancelInitialScrollAnimation();
    }

    renderedCallback() {
        this.runPendingInitialScrollAnimation();

        if (!this._pendingScrollFeedItemId) {
            return;
        }

        const feedItemId = this._pendingScrollFeedItemId;
        const listItem = this.template.querySelector(`[data-feed-item-id="${feedItemId}"]`);
        if (!listItem) {
            return;
        }

        const postComponent = listItem.querySelector('c-communicator-chatter-history-post');
        if (!postComponent) {
            return;
        }

        if (this._pendingScrollFeedCommentId) {
            postComponent.navigateToComment(this._pendingScrollFeedCommentId);
            this._pendingScrollFeedItemId = null;
            this._pendingScrollFeedCommentId = null;
            this._pendingExpandComments = false;
            return;
        }

        if (this._pendingExpandComments) {
            postComponent.expandComments();
        }

        listItem.scrollIntoView({ behavior: 'smooth', block: 'center' });
        this._pendingScrollFeedItemId = null;
        this._pendingScrollFeedCommentId = null;
        this._pendingExpandComments = false;
    }

    get hasOpportunityId() {
        return !!this._opportunityId;
    }

    get hasThreadId() {
        return !!this._threadId;
    }

    get hasRequiredContext() {
        return this.hasOpportunityId && this.hasThreadId;
    }

    get showSearchBar() {
        return !this.useExternalSearch
            && !this.hideToolbar
            && this.initialLoadCompleted
            && this.posts.length > 0
            && !this.showErrorState;
    }

    get showClearSearch() {
        return !this.useExternalSearch && this.normalizedSearchTerm.length > 0;
    }

    get showInitialLoading() {
        return this.isLoading && !this.initialLoadCompleted;
    }

    get showNoOpportunityState() {
        return !this.hasRequiredContext && !this.isLoading;
    }

    get showErrorState() {
        return this.hasRequiredContext && this.errorMessage && this.posts.length === 0;
    }

    get showLoadedContent() {
        return this.hasRequiredContext && this.initialLoadCompleted && !this.showErrorState;
    }

    get showLoadMoreControls() {
        return !this.loadAllMessages && (this.hasMore || this.isLoadingMore);
    }

    get showInlineLoadMoreError() {
        return !!this.loadMoreErrorMessage && this.posts.length > 0;
    }

    get showCommentsTruncatedNotice() {
        return this.showLoadedContent && this.hasTruncatedComments;
    }

    get hasVisiblePosts() {
        return this.visiblePosts.length > 0;
    }

    get showHistoryEmptyState() {
        return this.showLoadedContent && this.posts.length === 0;
    }

    get showSearchEmptyState() {
        if (this.useExternalSearch) {
            return false;
        }

        return this.showLoadedContent
            && this.normalizedSearchTerm.length > 0
            && this.posts.length > 0
            && this.visiblePosts.length === 0;
    }

    get filteredPosts() {
        const normalizedSearchTerm = this.normalizedSearchTerm;
        if (!normalizedSearchTerm) {
            return this.posts;
        }

        return this.posts.filter((post) => this.matchesSearch(post, normalizedSearchTerm));
    }

    get visiblePosts() {
        const basePosts = this.useExternalSearch ? this.posts : this.filteredPosts;
        return (basePosts || []).map((post) => ({
            ...post,
            isHighlighted: post.feedItemId === this.highlightedFeedItemId,
            highlightedCommentId: this.highlightedFeedCommentId
        }));
    }

    get normalizedSearchTerm() {
        return this.normalizeSearchValue(this.effectiveSearchTerm);
    }

    get serverSearchTerm() {
        return String(this.effectiveSearchTerm || '').trim();
    }

    get effectiveSearchTerm() {
        return this.useExternalSearch ? this.externalSearchTerm : this.searchTerm;
    }

    get toolbarCaption() {
        if (!this.hasOpportunityId) {
            return 'Aguardando uma oportunidade válida para carregar o histórico.';
        }
        if (this.posts.length === 0 && this.initialLoadCompleted) {
            return 'Consulta somente leitura para posts, comentários e anexos acessíveis.';
        }
        return 'Consulta somente leitura para o histórico carregado desta oportunidade.';
    }

    get searchHintText() {
        const totalLabel = `${this.posts.length} ${this.posts.length === 1 ? 'post carregado' : 'posts carregados'}`;
        if (this.normalizedSearchTerm.length > 0) {
            return `Busca local em ${totalLabel}. Exibindo ${this.visiblePosts.length} ${this.visiblePosts.length === 1 ? 'post' : 'posts'}.`;
        }
        return `Busca considera somente o histórico já carregado. Atualmente há ${totalLabel}.`;
    }

    get rootClass() {
        const classes = ['comm-chatter-history'];
        if (this.embedded) {
            classes.push('comm-chatter-history--embedded');
        }
        return classes.join(' ');
    }

    get bodyClass() {
        const classes = ['comm-chatter-history__body'];
        if (this.embedded && this.loadAllMessages) {
            classes.push('comm-chatter-history__body--compact');
        }
        if (this._pendingInitialScrollAnimation) {
            classes.push('comm-chatter-history__body--preparing-initial-scroll');
        }
        return classes.join(' ');
    }

    get showCompactBottomSentinel() {
        return this.embedded && this.loadAllMessages && this.showLoadedContent;
    }

    get pagingDirection() {
        return PAGING_DIRECTION_NEWER;
    }

    get showToolbar() {
        return !this.hideToolbar;
    }

    get showSearchHint() {
        return this.showSearchBar && !this.useExternalSearch;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
    }

    handleClearSearch() {
        this.searchTerm = '';
    }

    handleRetry() {
        if (!this.hasRequiredContext || this.isLoading) {
            return;
        }
        this.loadFirstPageForCurrentContext().catch(() => {});
    }

    handleLoadMore() {
        if (!this.hasRequiredContext || this.isLoading || this.isLoadingMore) {
            return;
        }
        if (this.loadAllMessages) {
            if (!this.hasMore || !this.previousPageCursor || this._isLoadingRemainingPages) {
                return;
            }
            this.startRemainingPagesLoadForCurrentContext();
            return;
        }
        if (!this.previousPageCursor) {
            return;
        }
        this.loadNewerPage();
    }

    async handleNavigateFile(event) {
        if (!this.openFilesInNewTab) {
            this.dispatchEvent(new CustomEvent('navigatefile', {
                detail: event.detail,
                bubbles: true,
                composed: true
            }));
            return;
        }

        event.stopPropagation();

        const detail = event.detail || {};
        const contentDocumentId = String(detail.contentDocumentId || '').trim();
        const contentVersionId = String(detail.contentVersionId || '').trim();

        if (!this.hasRequiredContext || (!contentDocumentId && !contentVersionId)) {
            return;
        }

        try {
            const attachment = await getAttachmentFile({
                threadId: this._threadId,
                opportunityId: this._opportunityId,
                contentDocumentId: contentDocumentId || null,
                contentVersionId: contentVersionId || null,
                feedItemId: detail.feedItemId || null,
                feedCommentId: detail.feedCommentId || null
            });
            this.openAttachmentFromBase64(attachment);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to open chatter attachment', error);
        }
    }

    openAttachmentFromBase64(attachment) {
        openCommunicatorAttachmentFromBase64(attachment);
    }

    @api
    async navigateToFeedItem(feedItemId, options = {}) {
        const normalizedFeedItemId = this.normalizeId(feedItemId);
        if (!normalizedFeedItemId || !this.hasRequiredContext) {
            return false;
        }

        const normalizedFeedCommentId = this.normalizeId(options.feedCommentId);
        const shouldExpandComments = options.expandComments === true || !!normalizedFeedCommentId;

        this.highlightedFeedItemId = null;
        this.highlightedFeedCommentId = null;
        this._pendingScrollFeedItemId = null;
        this._pendingScrollFeedCommentId = null;
        this._pendingExpandComments = false;

        const foundLocally = this.hasPostLoaded(normalizedFeedItemId)
            || await this.ensureFeedItemLoaded(normalizedFeedItemId);

        if (!foundLocally) {
            return false;
        }

        this.highlightedFeedItemId = normalizedFeedCommentId ? null : normalizedFeedItemId;
        this.highlightedFeedCommentId = normalizedFeedCommentId;
        this._pendingScrollFeedItemId = normalizedFeedItemId;
        this._pendingScrollFeedCommentId = normalizedFeedCommentId;
        this._pendingExpandComments = shouldExpandComments;
        return true;
    }

    async loadFirstPage() {
        const contextVersion = this._contextVersion;
        const requestedOpportunityId = this._opportunityId;
        const requestedThreadId = this._threadId;
        let shouldLoadRemainingPages = false;

        this.isLoading = true;
        this.initialLoadCompleted = false;
        this.errorMessage = '';
        this.loadMoreErrorMessage = '';
        this.posts = [];
        this.previousPageCursor = null;
        this.hasMore = false;
        this.hasTruncatedComments = false;
        this.cancelInitialScrollAnimation();

        try {
            const page = await getChatterHistoryPage({
                threadId: requestedThreadId,
                opportunityId: requestedOpportunityId,
                cursor: null,
                pageSize: this.pageSize,
                pagingDirection: this.pagingDirection
            });
            const response = page && typeof page === 'object' ? page : {};

            if (!this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                return;
            }

            const loadedPosts = this.preparePostsForRender(Array.isArray(response.posts) ? response.posts : []);
            this.prepareInitialScrollAnimation(loadedPosts);
            this.posts = loadedPosts;
            this.previousPageCursor = response.previousPageCursor || null;
            this.hasMore = response.hasMore === true;
            this.hasTruncatedComments = response.commentsTruncated === true;
            this.initialLoadCompleted = true;
            this.isLoading = false;
            shouldLoadRemainingPages = this.loadAllMessages && this.hasMore && !!this.previousPageCursor;
            if (shouldLoadRemainingPages) {
                this.startRemainingPagesLoad({
                    contextVersion,
                    opportunityId: requestedOpportunityId,
                    threadId: requestedThreadId,
                    initialCursor: this.previousPageCursor
                });
            }
            if (this.useExternalSearch) {
                await this.performSearchForCurrentState();
            }
        } catch (error) {
            if (!this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                return;
            }

            this.errorMessage = this.extractErrorMessage(error);
            this.initialLoadCompleted = true;
            this.notifyError(this.errorMessage, 'initial');
        } finally {
            if (this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                this.isLoading = false;
            }
        }
    }

    async loadNewerPage() {
        const contextVersion = this._contextVersion;
        const requestedOpportunityId = this._opportunityId;
        const requestedThreadId = this._threadId;
        const requestedCursor = this.previousPageCursor;

        this.isLoadingMore = true;
        this.loadMoreErrorMessage = '';

        try {
            const page = await getChatterHistoryPage({
                threadId: requestedThreadId,
                opportunityId: requestedOpportunityId,
                cursor: requestedCursor,
                pageSize: this.pageSize,
                pagingDirection: PAGING_DIRECTION_NEWER
            });
            const response = page && typeof page === 'object' ? page : {};

            if (!this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                return;
            }

            const newerPosts = this.preparePostsForRender(Array.isArray(response.posts) ? response.posts : []);
            const mergedPosts = this.mergeNewerPosts(this.posts, newerPosts);
            const addedCount = mergedPosts.length - this.posts.length;

            this.posts = mergedPosts;
            this.previousPageCursor = response.previousPageCursor || null;
            this.hasMore = response.hasMore === true;
            this.hasTruncatedComments = this.hasTruncatedComments || response.commentsTruncated === true;

            this.dispatchEvent(new CustomEvent('loadnewer', {
                detail: {
                    addedCount,
                    hasMore: this.hasMore
                },
                bubbles: true,
                composed: true
            }));
        } catch (error) {
            if (!this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                return;
            }

            this.loadMoreErrorMessage = this.extractErrorMessage(error);
            this.notifyError(this.loadMoreErrorMessage, 'newer');
        } finally {
            if (this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                this.isLoadingMore = false;
            }
        }
    }

    startRemainingPagesLoadForCurrentContext() {
        return this.startRemainingPagesLoad({
            contextVersion: this._contextVersion,
            opportunityId: this._opportunityId,
            threadId: this._threadId,
            initialCursor: this.previousPageCursor
        });
    }

    startRemainingPagesLoad({ contextVersion, opportunityId, threadId, initialCursor }) {
        if (!this.loadAllMessages
            || !initialCursor
            || !this.hasMore
            || !this.isContextValid(contextVersion, opportunityId, threadId)) {
            return null;
        }

        if (this._remainingPagesLoadPromise) {
            return this._remainingPagesLoadPromise;
        }

        this._isLoadingRemainingPages = true;
        this.loadMoreErrorMessage = '';

        let loadPromise;
        loadPromise = (async () => {
            let cursor = initialCursor;
            let hasMorePages = this.hasMore === true && !!cursor;

            await this.waitForNextAnimationFrame();
            if (!this.isContextValid(contextVersion, opportunityId, threadId)) {
                this.resolveRemainingPagesWaiters(contextVersion, { madeProgress: false, done: true, stale: true });
                return;
            }

            try {
                while (hasMorePages && cursor) {
                    const page = await getChatterHistoryPage({
                        threadId,
                        opportunityId,
                        cursor,
                        pageSize: this.pageSize,
                        pagingDirection: PAGING_DIRECTION_NEWER
                    });
                    const response = page && typeof page === 'object' ? page : {};

                    if (!this.isContextValid(contextVersion, opportunityId, threadId)) {
                        this.resolveRemainingPagesWaiters(contextVersion, { madeProgress: false, done: true, stale: true });
                        return;
                    }

                    const newerPosts = this.preparePostsForRender(Array.isArray(response.posts) ? response.posts : []);
                    const addedCount = this.integrateNewerPostsProgressively(newerPosts);
                    if (!this.isContextValid(contextVersion, opportunityId, threadId)) {
                        this.resolveRemainingPagesWaiters(contextVersion, { madeProgress: false, done: true, stale: true });
                        return;
                    }

                    cursor = response.previousPageCursor || null;
                    hasMorePages = response.hasMore === true && !!cursor;
                    this.previousPageCursor = cursor;
                    this.hasMore = hasMorePages;
                    this.hasTruncatedComments = this.hasTruncatedComments || response.commentsTruncated === true;
                    this.resolveRemainingPagesWaiters(contextVersion, {
                        madeProgress: addedCount > 0,
                        done: !hasMorePages
                    });
                }
            } catch (error) {
                if (!this.isContextValid(contextVersion, opportunityId, threadId)) {
                    this.resolveRemainingPagesWaiters(contextVersion, { madeProgress: false, done: true, stale: true });
                    return;
                }

                this.loadMoreErrorMessage = this.extractErrorMessage(error);
                this.notifyError(this.loadMoreErrorMessage, 'older');
                this.resolveRemainingPagesWaiters(contextVersion, {
                    madeProgress: false,
                    done: true,
                    error: true
                });
            } finally {
                if (this._remainingPagesLoadPromise === loadPromise) {
                    this._remainingPagesLoadPromise = null;
                    this._isLoadingRemainingPages = false;
                }
            }
        })();

        this._remainingPagesLoadPromise = loadPromise;
        return loadPromise;
    }

    integrateNewerPostsProgressively(newerPosts) {
        const currentPosts = Array.isArray(this.posts) ? this.posts : [];
        const mergedPosts = this.mergeNewerPosts(currentPosts, newerPosts);
        const addedCount = mergedPosts.length - currentPosts.length;
        if (addedCount <= 0) {
            return 0;
        }

        this.posts = mergedPosts;
        return addedCount;
    }

    resetState() {
        this.posts = [];
        this.searchTerm = '';
        this.searchResults = [];
        this.previousPageCursor = null;
        this.hasMore = false;
        this.isLoading = false;
        this.isLoadingMore = false;
        this.isSearching = false;
        this.searchCompleted = false;
        this.initialLoadCompleted = false;
        this.errorMessage = '';
        this.loadMoreErrorMessage = '';
        this.hasTruncatedComments = false;
        this.highlightedFeedItemId = null;
        this.highlightedFeedCommentId = null;
        this._pendingScrollFeedItemId = null;
        this._pendingScrollFeedCommentId = null;
        this._pendingExpandComments = false;
        this._remainingPagesLoadPromise = null;
        this._isLoadingRemainingPages = false;
        this.resolveAllRemainingPagesWaiters({ madeProgress: false, done: true, stale: true });
        this._searchVersion += 1;
        this.cancelInitialScrollAnimation();
        this.dispatchSearchStateChange();
    }

    prepareInitialScrollAnimation(posts) {
        this.cancelInitialScrollAnimation();
        this._pendingInitialScrollAnimation = this.loadAllMessages && Array.isArray(posts) && posts.length > 0;
    }

    runPendingInitialScrollAnimation() {
        if (!this._pendingInitialScrollAnimation) {
            return;
        }

        const scrollContainer = this.template.querySelector('.comm-chatter-history__body');
        if (!scrollContainer) {
            return;
        }

        if (this._pendingScrollFeedItemId) {
            this.cancelInitialScrollAnimation();
            scrollContainer.classList.remove('comm-chatter-history__body--preparing-initial-scroll');
            return;
        }

        const topSentinel = this.template.querySelector('.comm-chatter-history__top-sentinel');
        const maxScrollTop = Math.max(0, scrollContainer.scrollHeight - scrollContainer.clientHeight);
        if (maxScrollTop <= 0) {
            this._pendingInitialScrollAnimation = false;
            scrollContainer.classList.remove('comm-chatter-history__body--preparing-initial-scroll');
            return;
        }

        this._pendingInitialScrollAnimation = false;
        scrollContainer.classList.remove('comm-chatter-history__body--preparing-initial-scroll');
        if (!topSentinel || typeof topSentinel.scrollIntoView !== 'function') {
            return;
        }

        scrollContainer.scrollTop = maxScrollTop;
        this._initialScrollAnimationFrame = this.requestAnimationFrame(() => {
            this._initialScrollAnimationFrame = null;
            if (!this._isConnected || !this.hasRequiredContext) {
                return;
            }
            topSentinel.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
    }

    requestAnimationFrame(callback) {
        if (typeof window !== 'undefined' && typeof window.requestAnimationFrame === 'function') {
            return window.requestAnimationFrame(callback);
        }
        callback();
        return null;
    }

    waitForNextAnimationFrame() {
        return new Promise((resolve) => {
            let resolved = false;
            this.requestAnimationFrame(() => {
                if (resolved) {
                    return;
                }
                resolved = true;
                resolve();
            });
        });
    }

    cancelInitialScrollAnimation() {
        this._pendingInitialScrollAnimation = false;
        if (this._initialScrollAnimationFrame === null) {
            return;
        }
        if (typeof window !== 'undefined' && typeof window.cancelAnimationFrame === 'function') {
            window.cancelAnimationFrame(this._initialScrollAnimationFrame);
        }
        this._initialScrollAnimationFrame = null;
    }

    async loadFirstPageForCurrentContext() {
        const requestedContextVersion = this._contextVersion;
        const requestedOpportunityId = this._opportunityId;
        const requestedThreadId = this._threadId;
        await this.ensureConfigLoaded();
        if (!this._isConnected
            || !requestedOpportunityId
            || !requestedThreadId
            || requestedContextVersion !== this._contextVersion
            || requestedOpportunityId !== this._opportunityId
            || requestedThreadId !== this._threadId) {
            return;
        }
        await this.loadFirstPage();
    }

    async ensureConfigLoaded() {
        if (this._hasLoadedConfig) {
            return;
        }

        if (!this._configPromise) {
            this._configPromise = this.loadConfig()
                .finally(() => {
                    this._hasLoadedConfig = true;
                    this._configPromise = null;
                });
        }

        await this._configPromise;
    }

    async loadConfig() {
        try {
            const settings = await getSettings();
            if (settings?.messagesPerPage > 0) {
                this.pageSize = settings.messagesPerPage;
            }
            if (typeof settings?.chatterHistoryEmptyMessage === 'string'
                && settings.chatterHistoryEmptyMessage.trim()) {
                this.chatterHistoryEmptyMessage = settings.chatterHistoryEmptyMessage.trim();
            }
        } catch (error) {
            this.pageSize = null;
        }
    }

    async performSearchForCurrentState() {
        if (!this.useExternalSearch) {
            return;
        }

        const normalizedSearchTerm = this.normalizedSearchTerm;
        const rawSearchTerm = this.serverSearchTerm;
        if (!this.hasRequiredContext || normalizedSearchTerm.length < MIN_SEARCH_TERM_LENGTH) {
            this.searchResults = [];
            this.isSearching = false;
            this.searchCompleted = false;
            this.dispatchSearchStateChange();
            return;
        }

        const searchVersion = ++this._searchVersion;
        const requestedOpportunityId = this._opportunityId;
        const requestedThreadId = this._threadId;

        this.isSearching = true;
        this.searchCompleted = false;
        this.dispatchSearchStateChange();

        try {
            const rawResults = await searchChatterHistory({
                threadId: requestedThreadId,
                opportunityId: requestedOpportunityId,
                keyword: rawSearchTerm
            });

            if (!this.isSearchContextValid(searchVersion, requestedOpportunityId, requestedThreadId, normalizedSearchTerm)) {
                return;
            }

            this.searchResults = this.prepareSearchResults(rawResults);
            this.searchCompleted = true;
        } catch (error) {
            if (!this.isSearchContextValid(searchVersion, requestedOpportunityId, requestedThreadId, normalizedSearchTerm)) {
                return;
            }

            this.searchResults = [];
            this.searchCompleted = true;
            this.notifyError(this.extractErrorMessage(error), 'search');
        } finally {
            if (this.isSearchContextValid(searchVersion, requestedOpportunityId, requestedThreadId, normalizedSearchTerm)) {
                this.isSearching = false;
                this.dispatchSearchStateChange();
            }
        }
    }

    isContextValid(contextVersion, opportunityId, threadId) {
        return this._isConnected
            && contextVersion === this._contextVersion
            && opportunityId === this._opportunityId
            && threadId === this._threadId;
    }

    isSearchContextValid(searchVersion, opportunityId, threadId, normalizedSearchTerm) {
        return this._isConnected
            && searchVersion === this._searchVersion
            && opportunityId === this._opportunityId
            && threadId === this._threadId
            && normalizedSearchTerm === this.normalizedSearchTerm;
    }

    mergeNewerPosts(currentPosts, newerPosts) {
        const seenFeedItemIds = new Set((currentPosts || []).map((post) => String(post.feedItemId || '')));
        const uniqueNewerPosts = [];

        (newerPosts || []).forEach((post) => {
            const postKey = String(post.feedItemId || '');
            if (!postKey || seenFeedItemIds.has(postKey)) {
                return;
            }
            seenFeedItemIds.add(postKey);
            uniqueNewerPosts.push(post);
        });

        return [...(currentPosts || []), ...uniqueNewerPosts];
    }

    preparePostsForRender(posts) {
        if (!Array.isArray(posts) || posts.length === 0) {
            return [];
        }

        return posts.map((post) => ({
            ...post,
            attachments: this.mergeInlineImagesIntoAttachments(post.attachments, post.inlineImages),
            comments: Array.isArray(post.comments)
                ? post.comments.map((comment) => ({
                    ...comment,
                    attachments: this.mergeInlineImagesIntoAttachments(comment.attachments, comment.inlineImages)
                }))
                : []
        }));
    }

    prepareSearchResults(rawResults) {
        return (Array.isArray(rawResults) ? rawResults : []).map((result) => ({
            Id: this.normalizeId(result.feedItemId),
            Thread__c: this._threadId,
            Body__c: result.previewText || '',
            senderName: result.authorName || 'Usuário do Chatter',
            formattedTime: this.formatDateTime(result.createdDate),
            stageName: result.originLabel || '',
            expandComments: result.expandComments === true,
            feedCommentId: this.normalizeId(result.feedCommentId)
        })).filter((result) => !!result.Id);
    }

    mergeInlineImagesIntoAttachments(attachments, inlineImages) {
        const mergedAttachments = Array.isArray(attachments)
            ? attachments.filter(Boolean)
            : [];
        if (!Array.isArray(inlineImages) || inlineImages.length === 0) {
            return mergedAttachments;
        }

        const seenContentDocumentIds = new Set(
            mergedAttachments
                .map((attachment) => this.normalizeId(attachment?.contentDocumentId))
                .filter(Boolean)
        );

        inlineImages.forEach((inlineImage, index) => {
            const contentDocumentId = this.normalizeId(inlineImage?.contentDocumentId);
            if (!contentDocumentId || seenContentDocumentIds.has(contentDocumentId)) {
                return;
            }

            const attachment = this.buildAttachmentFromInlineImage(inlineImage, index);
            if (!attachment) {
                return;
            }

            mergedAttachments.push(attachment);
            seenContentDocumentIds.add(contentDocumentId);
        });

        return mergedAttachments;
    }

    buildAttachmentFromInlineImage(inlineImage, index) {
        const contentDocumentId = this.normalizeId(inlineImage?.contentDocumentId);
        const contentVersionId = this.normalizeId(inlineImage?.contentVersionId);
        if (!contentDocumentId && !contentVersionId) {
            return null;
        }

        return {
            contentDocumentId,
            contentVersionId,
            title: inlineImage?.title || inlineImage?.altText || 'Imagem do Chatter',
            extension: inlineImage?.extension || null,
            size: inlineImage?.size || null,
            fileType: inlineImage?.fileType || null,
            isImage: inlineImage?.isImage === true,
            stableKey: inlineImage?.stableKey || `inline-attachment:${contentDocumentId || contentVersionId}:${index}`
        };
    }

    matchesSearch(post, normalizedSearchTerm) {
        const values = [
            post.bodyText,
            post.authorName,
            post.originLabel,
            ...(post.attachments || []).map((attachment) => attachment.title),
            ...this.collectCommentSearchValues(post)
        ];

        return values.some((value) => this.normalizeSearchValue(value).includes(normalizedSearchTerm));
    }

    collectCommentSearchValues(post) {
        const values = [];
        (post.comments || []).forEach((comment) => {
            values.push(comment.bodyText);
            values.push(comment.authorName);
            (comment.attachments || []).forEach((attachment) => {
                values.push(attachment.title);
            });
        });
        return values;
    }

    normalizeSearchValue(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' ');
    }

    normalizeId(value) {
        const normalizedValue = String(value || '').trim();
        return normalizedValue || null;
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }

        const dateValue = value instanceof Date ? value : new Date(value);
        if (Number.isNaN(dateValue.getTime())) {
            return '';
        }

        return dateValue.toLocaleString('pt-BR', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    hasPostLoaded(feedItemId) {
        return (this.posts || []).some((post) => post.feedItemId === feedItemId);
    }

    async ensureFeedItemLoaded(feedItemId) {
        if (this.loadAllMessages) {
            while (!this.hasPostLoaded(feedItemId)) {
                if (this._remainingPagesLoadPromise) {
                    const progress = await this.waitForRemainingPagesProgress(this._contextVersion);
                    if (!progress || progress.done === true) {
                        break;
                    }
                    continue;
                }

                if (!this.hasMore || !this.previousPageCursor) {
                    break;
                }

                const loadPromise = this.startRemainingPagesLoadForCurrentContext();
                if (!loadPromise) {
                    break;
                }
            }

            return this.hasPostLoaded(feedItemId);
        }

        return this.loadPageForFeedItem(feedItemId);
    }

    async loadPageForFeedItem(feedItemId) {
        if (!feedItemId || !this.hasRequiredContext || this.isLoading || this.isLoadingMore) {
            return false;
        }

        const contextVersion = this._contextVersion;
        const requestedOpportunityId = this._opportunityId;
        const requestedThreadId = this._threadId;

        this.isLoadingMore = true;
        this.loadMoreErrorMessage = '';
        this.cancelInitialScrollAnimation();

        try {
            const page = await getChatterHistoryPageForFeedItem({
                threadId: requestedThreadId,
                opportunityId: requestedOpportunityId,
                feedItemId,
                pageSize: this.pageSize
            });
            const response = page && typeof page === 'object' ? page : {};

            if (!this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                return false;
            }

            this.posts = this.preparePostsForRender(Array.isArray(response.posts) ? response.posts : []);
            this.previousPageCursor = response.previousPageCursor || null;
            this.hasMore = response.hasMore === true;
            this.hasTruncatedComments = response.commentsTruncated === true;
            this.initialLoadCompleted = true;
        } catch (error) {
            if (!this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                return false;
            }

            this.loadMoreErrorMessage = this.extractErrorMessage(error);
            this.notifyError(this.loadMoreErrorMessage, 'navigation');
            return false;
        } finally {
            if (this.isContextValid(contextVersion, requestedOpportunityId, requestedThreadId)) {
                this.isLoadingMore = false;
            }
        }

        return this.hasPostLoaded(feedItemId);
    }

    dispatchSearchStateChange() {
        if (!this.useExternalSearch) {
            return;
        }

        this.dispatchEvent(new CustomEvent('searchstatechange', {
            detail: {
                keyword: this._externalSearchTerm,
                results: this.searchResults,
                isSearching: this.isSearching,
                isComplete: this.searchCompleted
            },
            bubbles: true,
            composed: true
        }));
    }

    extractErrorMessage(error) {
        const body = error && error.body ? error.body : null;

        if (Array.isArray(body)) {
            const messages = body
                .map((item) => (item && item.message ? item.message : ''))
                .filter(Boolean);
            return messages.length > 0 ? messages.join(' ') : DEFAULT_ERROR_MESSAGE;
        }

        if (body && typeof body.message === 'string' && body.message.trim()) {
            return body.message.trim();
        }

        return DEFAULT_ERROR_MESSAGE;
    }

    notifyError(message, phase) {
        this.dispatchEvent(new CustomEvent('error', {
            detail: { message, phase },
            bubbles: true,
            composed: true
        }));
    }

    waitForRemainingPagesProgress(contextVersion) {
        return new Promise((resolve) => {
            this._remainingPagesProgressWaiters.push({ contextVersion, resolve });
        });
    }

    resolveRemainingPagesWaiters(contextVersion, result) {
        const remainingWaiters = [];
        this._remainingPagesProgressWaiters.forEach((waiter) => {
            if (waiter.contextVersion === contextVersion) {
                waiter.resolve(result);
                return;
            }
            remainingWaiters.push(waiter);
        });
        this._remainingPagesProgressWaiters = remainingWaiters;
    }

    resolveAllRemainingPagesWaiters(result) {
        this._remainingPagesProgressWaiters.forEach((waiter) => waiter.resolve(result));
        this._remainingPagesProgressWaiters = [];
    }
}