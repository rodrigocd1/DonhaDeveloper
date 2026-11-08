import { LightningElement, api, track } from 'lwc';
import { NavigationMixin }                  from 'lightning/navigation';
import getOpportunityChatList               from '@salesforce/apex/CommunicatorChatController.getOpportunityChatList';
import getOpportunityUnreadMessageTotal     from '@salesforce/apex/CommunicatorChatController.getOpportunityUnreadMessageTotal';
import getSettings                          from '@salesforce/apex/CommunicatorChatController.getSettings';
import getBroadcastUnreadTotal              from '@salesforce/apex/CommunicatorChatController.getBroadcastUnreadTotal';
import getOpportunityRelatedRefs            from '@salesforce/apex/CommunicatorChatController.getOpportunityRelatedRefs';
import getGroupsWithStats                   from '@salesforce/apex/CommunicatorChatController.getGroupsWithStats';
import getRecentlyViewedThreadCards         from '@salesforce/apex/CommunicatorChatController.getRecentlyViewedThreadCards';
import markThreadAsRecentlyViewed           from '@salesforce/apex/CommunicatorChatController.markThreadAsRecentlyViewed';

const DEFAULT_PAGE_SIZE  = 10;
const DEBOUNCE_MS        = 350;
const DEFAULT_POLL_MS    = 10000;
const MIN_POLL_MS        = 3000;
const RECENT_ORDER_LIMIT = 2000;
const PRIMARY_VIEW_CONVERSATIONS = 'conversations';
const PRIMARY_VIEW_BROADCAST     = 'broadcast';

const RELATED_REF_NOT_FOUND_LABEL_BY_STAGE = Object.freeze({
    opportunity_negociacao:      'Cotação - Não localizada',
    opportunity_analise_renda:   'AR - Não localizada',
    opportunity_analise_credito: 'AR e AB - Não localizadas'
});

export default class CommunicatorChatHistory extends NavigationMixin(LightningElement) {

    @api isModal = false;
    @api viewedGroupIds = [];

    @track threads              = [];
    @track totalCount           = 0;
    @track isLoading            = false;
    @track activeFilter         = 'all';
    @track activePrimaryView    = PRIMARY_VIEW_CONVERSATIONS;
    @track _unreadTabCount      = 0;
    @track keyword              = '';
    @track currentPage          = 1;
    @track isMaximized          = false;
    @track showStageDropdown    = false;
    @track _stageFilters        = [];
    @track _etapaFilter         = '';
    @track pageSize             = DEFAULT_PAGE_SIZE;
    @track gotoPageValue        = '';

    // Groups tab
    @track _groups              = [];
    @track _isLoadingGroups     = false;
    @track showCreateGroupModal = false;
    @track _broadcastAuthoringContext = {
        canCreateBroadcast: false,
        uploadConfigValid: true,
        uploadConfigErrorMessage: '',
        maxUploadBroadcastFileSizeMB: null
    };
    @track broadcastUnreadTotal = 0;
    @track broadcastImagePreview = null;

    @track _hasPermission       = true;
    @track _noPermissionMessage = '';

    _debounceTimer      = null;
    _rawThreads         = [];
    _searchResults      = null; // null = not searching; array = server search results for current keyword
    _pollTimer          = null;
    _pollIntervalMs     = DEFAULT_POLL_MS;
    _hasGroupAccess     = false;
    _relatedRefsByOpportunityId = {};
    _isConnected = false;
    _broadcastUnreadRequestVersion = 0;
    _broadcastUnreadInFlight = false;
    _broadcastUnreadRefreshQueued = false;
    _broadcastImagePreviewReturnFocus = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    async connectedCallback() {
        this._isConnected = true;
        await this._loadConfig();
        if (!this._hasPermission) return;
        this._load();
        this._loadGroups();
        this._startPolling();
        this._refreshBroadcastUnreadTotal();
    }

    disconnectedCallback() {
        this._isConnected = false;
        this._stopPolling();
        this._invalidateBroadcastUnreadRequests();
        this._clearBroadcastImagePreview();
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    handleBack() {
        this._closeBroadcastImagePreview({ notifyWorkspace: true });
        this._load();
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleToggleMaximize() {
        this.isMaximized = !this.isMaximized;
        this.dispatchEvent(new CustomEvent('togglemaximize', {
            detail: { maximized: this.isMaximized }
        }));
    }

    handleFilterSelect(event) {
        const filter = event.currentTarget.dataset.filter;
        if (filter === PRIMARY_VIEW_BROADCAST) {
            if (this.activePrimaryView === PRIMARY_VIEW_BROADCAST) return;
            this._resetConversationSelectionState();
            this.activePrimaryView = PRIMARY_VIEW_BROADCAST;
            this.showStageDropdown = false;
            this._refreshBroadcastUnreadTotal();
            return;
        }
        const wasBroadcast = this.activePrimaryView === PRIMARY_VIEW_BROADCAST;
        if (wasBroadcast) {
            this._closeBroadcastImagePreview({ notifyWorkspace: true });
            this.activePrimaryView = PRIMARY_VIEW_CONVERSATIONS;
        } else if (filter === this.activeFilter) {
            return;
        }
        this.activeFilter   = filter;
        this._resetConversationSelectionState();
        if (filter === 'groups') {
            this._loadGroups();
        } else {
            this._load();
        }
    }

    handleSearchInput(event) {
        this.keyword = event.target.value;
        if (this.showGroups) return; // enrichedGroups filtra pelo getter reativo
        clearTimeout(this._debounceTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this.currentPage = 1;
            const kw = this.keyword.trim();
            if (kw) {
                this._performServerSearch(kw);
            } else {
                this._searchResults = null;
                this._applyKeywordFilter();
            }
        }, DEBOUNCE_MS);
    }

    handleThreadSelect(event) {
        const threadId  = event.currentTarget.dataset.threadId;
        const recordId = event.currentTarget.dataset.recordId;
        const repasseOpportunityId = event.currentTarget.dataset.repasseOpportunityId;
        const recordName = event.currentTarget.dataset.recordName;
        if (threadId) {
            markThreadAsRecentlyViewed({ threadId }).catch(() => {});
        }
        this.dispatchEvent(new CustomEvent('threadselected', {
            detail: { threadId, recordId: repasseOpportunityId || recordId, recordName }
        }));
    }

    handleRelatedRefClick(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        const objectApiName = event.currentTarget.dataset.objectApiName || null;
        if (!recordId) return;
        this._navigateToRecord(recordId, objectApiName);
    }

    _navigateToRecord(recordId, objectApiName) {
        if (this._isOpportunityRecord(recordId, objectApiName) && this._isBrokerCommunityContext()) {
            this._navigateToBrokerCommunityDetail(recordId);
            return;
        }
        const attributes = {
            recordId,
            actionName: 'view'
        };
        if (objectApiName) {
            attributes.objectApiName = objectApiName;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes
        });
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

    get isBroadcastCommunityContext() {
        return this._isBrokerCommunityContext();
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

    handlePrevPage() {
        if (this.currentPage <= 1) return;
        this.currentPage--;
        this._applyKeywordFilter();
    }

    handleNextPage() {
        if (this.currentPage >= this.totalPages) return;
        this.currentPage++;
        this._applyKeywordFilter();
    }

    handleFirstPage() {
        if (this.currentPage <= 1) return;
        this.currentPage = 1;
        this._applyKeywordFilter();
    }

    handleLastPage() {
        if (this.currentPage >= this.totalPages) return;
        this.currentPage = this.totalPages;
        this._applyKeywordFilter();
    }

    handlePageSelect(event) {
        const page = Number(event.currentTarget.dataset.page);
        if (!page || page === this.currentPage) return;
        this.currentPage = page;
        this._applyKeywordFilter();
    }

    handleGotoInput(event) {
        this.gotoPageValue = event.target.value;
    }

    handleGotoPage() {
        const page = Number(this.gotoPageValue);
        if (!page) return;
        const targetPage = Math.min(Math.max(page, 1), this.totalPages);
        if (targetPage === this.currentPage) {
            this.gotoPageValue = String(targetPage);
            return;
        }
        this.currentPage = targetPage;
        this.gotoPageValue = String(targetPage);
        this._applyKeywordFilter();
    }

    handleGotoKeydown(event) {
        if (event.key === 'Enter') {
            this.handleGotoPage();
        }
    }

    handleToggleStageFilter() {
        this.showStageDropdown = !this.showStageDropdown;
    }

    handleCloseStageDropdown() {
        this.showStageDropdown = false;
    }

    handleEtapaChange(event) {
        this._etapaFilter = event.target.value;
        this._stageFilters = [];
        this.currentPage  = 1;
        this._applyKeywordFilter();
    }

    handleStageChange(event) {
        const val = event.target.value;
        if (event.target.checked) {
            this._stageFilters = [...this._stageFilters, val];
        } else {
            this._stageFilters = this._stageFilters.filter(v => v !== val);
        }
        this.currentPage = 1;
        this._applyKeywordFilter();
    }

    handleClearFilters() {
        this._stageFilters     = [];
        this._etapaFilter      = '';
        this.showStageDropdown = false;
        this.currentPage       = 1;
        this._applyKeywordFilter();
    }

    // ─────────────────────────────────────────
    // Groups tab handlers
    // ─────────────────────────────────────────

    handleGroupSelect(event) {
        const groupId = event.currentTarget.dataset.groupId;
        const group   = this._groups.find(g => g.groupId === groupId);
        if (!group) return;
        const enriched = this.enrichedGroups.find(g => g.groupId === groupId);
        this._groups = this._groups.map(g =>
            g.groupId === groupId ? { ...g, unreadMentionCount: 0 } : g
        );
        this.dispatchEvent(new CustomEvent('groupselected', {
            detail: { group: enriched || { ...group } }
        }));
    }

    handleOpenCreateGroup() {
        this.showCreateGroupModal = true;
    }

    handleCreateGroupClose() {
        this.showCreateGroupModal = false;
    }

    handleGroupCreated() {
        this.showCreateGroupModal = false;
        this._loadGroups();
    }

    handleBroadcastAuthoringContext(event) {
        const context = event?.detail || {};
        this._broadcastAuthoringContext = {
            canCreateBroadcast: context.canCreateBroadcast === true,
            uploadConfigValid: context.uploadConfigValid !== false,
            uploadConfigErrorMessage: context.uploadConfigErrorMessage || '',
            maxUploadBroadcastFileSizeMB: context.maxUploadBroadcastFileSizeMB ?? null
        };
    }

    handleOpenCreateBroadcast() {
        this.template.querySelector('c-communicator-broadcast-workspace')?.openCreateDialog();
    }

    handleBroadcastUnreadChange() {
        this._refreshBroadcastUnreadTotal();
    }

    handleBroadcastImagePreviewOpen(event) {
        const src = String(event?.detail?.src || '').trim();
        if (!src) return;

        this._broadcastImagePreviewReturnFocus = this._resolveBroadcastImagePreviewFocusTarget();
        const fileName = String(event?.detail?.fileName || '').trim() || 'Imagem anexada';
        this.broadcastImagePreview = {
            src,
            fileName,
            alternativeText: String(event?.detail?.alternativeText || '').trim() || `Imagem anexada: ${fileName}`
        };
    }

    handleBroadcastImagePreviewClose() {
        this._closeBroadcastImagePreview({ notifyWorkspace: true, restoreFocus: true });
    }

    handleBroadcastImagePreviewReset() {
        this._closeBroadcastImagePreview();
    }

    get hasBroadcastUnread() {
        return this.broadcastUnreadTotal > 0;
    }

    get broadcastBadgeLabel() {
        return this.broadcastUnreadTotal > 99 ? '99+' : String(this.broadcastUnreadTotal);
    }

    get broadcastBadgeAccessibilityLabel() {
        return this.broadcastUnreadTotal > 99
            ? 'Mais de 99 mensagens não lidas em Comunicados'
            : this.broadcastUnreadTotal === 1
                ? '1 mensagem não lida em Comunicados'
                : `${this.broadcastUnreadTotal} mensagens não lidas em Comunicados`;
    }

    get broadcastBadgeClass() {
        return 'comm-history__tab-badge comm-history__tab-badge--broadcast';
    }

    // ─────────────────────────────────────────
    // Config & Polling
    // ─────────────────────────────────────────

    async _loadConfig() {
        try {
            const settings = await getSettings();
            if (settings.hasCommunicatorChatPermission === false) {
                this._hasPermission       = false;
                this._noPermissionMessage = settings.noPermissionMessage || '';
                return;
            }
            if (settings.pollingIntervalMs >= MIN_POLL_MS) {
                this._pollIntervalMs = settings.pollingIntervalMs;
            }
            if (settings.threadsPerPage > 0) {
                this.pageSize = settings.threadsPerPage;
            }
            this._hasGroupAccess = settings.hasGroupAccess === true;
        } catch (e) {
            this._hasPermission       = false;
            this._noPermissionMessage = 'Você não tem permissão para acessar as funcionalidades do canal de mensagens. Por favor, entre em contato com o Suporte de TI de vendas.';
        }
    }

    _startPolling() {
        this._stopPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => {
            this._refreshBroadcastUnreadTotal();
            if (this.activePrimaryView === PRIMARY_VIEW_BROADCAST) {
                this.template.querySelector('c-communicator-broadcast-workspace')?.refresh();
            } else if (this.activeFilter === 'groups') {
                this._loadGroups(true).catch(console.error);
            } else {
                this._load(true).catch(console.error);
                this._loadGroups(true).catch(console.error);
            }
        }, this._pollIntervalMs);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    _invalidateBroadcastUnreadRequests() {
        this._broadcastUnreadRequestVersion += 1;
        this._broadcastUnreadInFlight = false;
        this._broadcastUnreadRefreshQueued = false;
    }

    async _refreshBroadcastUnreadTotal() {
        if (!this._isConnected || !this._hasPermission) return;
        if (this._broadcastUnreadInFlight) {
            this._broadcastUnreadRefreshQueued = true;
            return;
        }

        const version = ++this._broadcastUnreadRequestVersion;
        this._broadcastUnreadInFlight = true;

        try {
            const total = await getBroadcastUnreadTotal();
            if (!this._isBroadcastUnreadRequestValid(version)) return;
            this.broadcastUnreadTotal = total || 0;
        } catch (e) {
            console.error('[communicatorChatHistory] _refreshBroadcastUnreadTotal:', e);
        } finally {
            this._broadcastUnreadInFlight = false;
            if (this._isBroadcastUnreadRequestValid(version) && this._broadcastUnreadRefreshQueued) {
                this._broadcastUnreadRefreshQueued = false;
                this._refreshBroadcastUnreadTotal();
            }
        }
    }

    _isBroadcastUnreadRequestValid(version) {
        return this._isConnected && version === this._broadcastUnreadRequestVersion;
    }

    // ─────────────────────────────────────────
    // Data
    // ─────────────────────────────────────────

    async _loadGroups(silent = false) {
        if (!silent) this._isLoadingGroups = true;
        try {
            this._groups = await getGroupsWithStats() || [];
        } catch (e) {
            console.error('communicatorChatHistory._loadGroups:', e);
            this._groups = [];
        } finally {
            if (!silent) this._isLoadingGroups = false;
            this._refreshBroadcastUnreadTotal();
        }
    }

    async _load(silent = false) {
        if (this.activeFilter === 'groups') {
            this._rawThreads = [];
            this.threads     = [];
            this.totalCount  = 0;
            return;
        }
        if (!silent) this.isLoading = true;
        try {
            const useRecentCards = this.activeFilter === 'all' && !String(this.keyword || '').trim();
            const [threads, unreadCount] = await Promise.all([
                useRecentCards
                    ? getRecentlyViewedThreadCards({ maxCount: RECENT_ORDER_LIMIT })
                    : getOpportunityChatList({ pageSize: 2000, offsetVal: 0, filter: this.activeFilter, keyword: '' }),
                getOpportunityUnreadMessageTotal({ pageSize: 2000, offsetVal: 0, keyword: '' })
            ]);
            this._rawThreads     = threads || [];
            this._unreadTabCount = unreadCount || 0;
            this._applyKeywordFilter();
            this._hydrateRelatedRefs().catch(() => {});
        } catch (e) {
            console.error('communicatorChatHistory._load:', e);
            this._rawThreads = [];
            this.threads     = [];
        } finally {
            if (!silent) this.isLoading = false;
            this._refreshBroadcastUnreadTotal();
        }
    }

    async _performServerSearch(kw) {
        this.isLoading = true;
        try {
            const results = await getOpportunityChatList({
                pageSize: 2000, offsetVal: 0, filter: this.activeFilter, keyword: kw
            });
            this._searchResults = results || [];
            this._applyKeywordFilter();
            this._hydrateRelatedRefs().catch(() => {});
        } catch (e) {
            console.error('communicatorChatHistory._performServerSearch:', e);
            this._searchResults = [];
        } finally {
            this.isLoading = false;
        }
    }

    async _hydrateRelatedRefs() {
        const allThreads = [...(this._rawThreads || []), ...(this._searchResults || [])];
        const ids = allThreads
            .map(t => t?.recordId)
            .filter(id => id && String(id).startsWith('006'));
        const unique  = [...new Set(ids)];
        const missing = unique.filter(id => !this._relatedRefsByOpportunityId[id]);
        if (missing.length === 0) return;
        const byId = await getOpportunityRelatedRefs({ opportunityIds: missing });
        if (!byId) return;
        this._relatedRefsByOpportunityId = { ...this._relatedRefsByOpportunityId, ...byId };
        // Re-apply filter so the new refs data is reflected in enrichedThreads
        this._applyKeywordFilter();
    }

    _effectiveRecordType(recordType, hasRepasse) {
        return hasRepasse || recordType === 'Repasse__c'
            ? 'Repasse__c'
            : 'Opportunity';
    }

    _displayStageForThread(thread) {
        if (thread.hasRepasse) {
            // currentStage = live Repasse macro phase (source of truth, e.g. 'Outros').
            // stageName = Stage__c of the selected thread, which may be an older phase.
            return thread.currentStage || thread.stageName || '';
        }
        return thread.currentStage || thread.stageName || '';
    }

    _getKeywordEtapaDedupedThreads() {
        const cardStage = t => this._displayStageForThread(t);

        // When a keyword is active, use server-side search results (all accessible records).
        // Otherwise fall back to the base list (only threads the user participated in or was mentioned in).
        let result = (this._searchResults !== null) ? [...this._searchResults] : [...this._rawThreads];

        if (this._etapaFilter) {
            result = result.filter(t => this._effectiveRecordType(t.recordType, t.hasRepasse) === this._etapaFilter);
        }
        if (this._stageFilters.length > 0) {
            result = result.filter(t => this._stageFilters.includes(cardStage(t)));
        }

        // When keyword search returns both an Opportunity DTO (hasRepasse=true) and a separate
        // Repasse DTO for the same thread, suppress the Opportunity card — mirrors compact's
        // _suppressOpportunityWhenRepasseExists logic.
        const repasseThreadIds = new Set(
            result
                .filter(t => t?.recordType === 'Repasse__c' && t?.threadId)
                .map(t => t.threadId)
        );
        if (repasseThreadIds.size > 0) {
            result = result.filter(t =>
                !(t?.recordType === 'Opportunity' && repasseThreadIds.has(t?.threadId))
            );
        }

        // Deduplicate to one card per record.
        // When a record has Repasse, keep the Repasse representation.
        const byRecord = new Map();
        for (const t of result) {
            const key = t.recordId || t.threadId;
            if (!key) continue;
            const current = byRecord.get(key);
            if (!current) {
                byRecord.set(key, t);
                continue;
            }
            const currIsRepasse = this._effectiveRecordType(current.recordType, current.hasRepasse) === 'Repasse__c';
            const nextIsRepasse = this._effectiveRecordType(t.recordType, t.hasRepasse) === 'Repasse__c';
            if (!currIsRepasse && nextIsRepasse) {
                byRecord.set(key, t);
            }
        }
        result = [...byRecord.values()];

        return result;
    }

    _parseListDateTime(dateValue) {
        const rawValue = String(dateValue || '').trim();
        const withSec = rawValue.match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/);
        if (withSec) {
            const [, d, mo, y, h, mi, s] = withSec;
            return new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s), 0).getTime();
        }
        const match = rawValue.match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2})$/);
        if (!match) return 0;
        const [, dayValue, monthValue, yearValue, hourValue, minuteValue] = match;
        return new Date(Number(yearValue), Number(monthValue) - 1, Number(dayValue), Number(hourValue), Number(minuteValue), 0, 0).getTime();
    }

    _applyKeywordFilter() {
        const cardStage = t => this._displayStageForThread(t);
        let result = this._getKeywordEtapaDedupedThreads();

        if (this._stageFilters.length > 0) {
            result = result.filter(t => this._stageFilters.includes(cardStage(t)));
        }

        const isDefaultView = this.activeFilter === 'all' && !this.keyword.trim();
        if (!isDefaultView && this.activeFilter === 'read') {
            // "Lidos": ordenado por quando o usuário leu a última notificação (ReadAt__c).
            result.sort((a, b) =>
                this._parseListDateTime(b.lastReadAt) - this._parseListDateTime(a.lastReadAt)
            );
        } else if (!isDefaultView) {
            result.sort((a, b) => {
                const aUnread = (a.unreadCount || 0) > 0;
                const bUnread = (b.unreadCount || 0) > 0;
                if (aUnread !== bUnread) return aUnread ? -1 : 1;
                return this._parseListDateTime(b.lastMessageAt) - this._parseListDateTime(a.lastMessageAt);
            });
        }

        // Client-side pagination over the full filtered+deduped set
        this.totalCount = result.length;
        if (this.totalPages > 0 && this.currentPage > this.totalPages) {
            this.currentPage = this.totalPages;
        } else if (result.length === 0) {
            this.currentPage = 1;
        }
        this.gotoPageValue = String(this.currentPage);
        const start = (this.currentPage - 1) * this.pageSize;
        this.threads = result.slice(start, start + this.pageSize);
    }

    _resetConversationSelectionState() {
        this.currentPage    = 1;
        this.keyword        = '';
        this._stageFilters  = [];
        this._etapaFilter   = '';
        this._rawThreads    = [];
        this.threads        = [];
        this._searchResults = null;
        this.showCreateGroupModal = false;
        this._closeBroadcastImagePreview({ notifyWorkspace: true });
    }

    _clearBroadcastImagePreview() {
        this.broadcastImagePreview = null;
        this._broadcastImagePreviewReturnFocus = null;
    }

    _closeBroadcastImagePreview({ notifyWorkspace = false, restoreFocus = false } = {}) {
        const hasPreview = !!this.broadcastImagePreview?.src;
        if (notifyWorkspace) {
            this.template.querySelector('c-communicator-broadcast-workspace')?.notifyImagePreviewClosed?.();
        }
        this.broadcastImagePreview = null;
        if (restoreFocus && hasPreview) {
            this._restoreBroadcastImagePreviewFocus();
            return;
        }
        this._broadcastImagePreviewReturnFocus = null;
    }

    _restoreBroadcastImagePreviewFocus() {
        const previousFocus = this._broadcastImagePreviewReturnFocus;
        const fallbackFocus = this._resolveBroadcastImagePreviewFallbackElement();
        this._broadcastImagePreviewReturnFocus = null;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            if (this._focusElement(previousFocus)) return;
            this._focusElement(fallbackFocus);
        }, 0);
    }

    _resolveBroadcastImagePreviewFocusTarget() {
        const activeElement = this.template.activeElement || document.activeElement || null;
        return this._isUsableFocusTarget(activeElement)
            ? activeElement
            : this._resolveBroadcastImagePreviewFallbackElement();
    }

    _resolveBroadcastImagePreviewFallbackElement() {
        return this.template.querySelector('[data-filter="broadcast"]');
    }

    _focusElement(element) {
        if (!element || typeof element.focus !== 'function') return false;
        try {
            element.focus();
            return true;
        } catch (error) {
            return false;
        }
    }

    _isUsableFocusTarget(element) {
        return !!element
            && element !== document.body
            && typeof element.focus === 'function';
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get totalPages()   { return Math.max(1, Math.ceil(this.totalCount / this.pageSize)); }
    get firstDisabled() { return this.currentPage <= 1; }
    get prevDisabled() { return this.currentPage <= 1; }
    get nextDisabled() { return this.currentPage >= this.totalPages; }
    get lastDisabled() { return this.currentPage >= this.totalPages; }
    get showGroups()             { return this.activeFilter === 'groups'; }
    get showCreateGroupButton()  { return this.showGroups && this._hasGroupAccess && this.activePrimaryView === PRIMARY_VIEW_CONVERSATIONS; }
    get showCreateBroadcastButton() {
        return !this.isModal
            && this.showBroadcastView
            && this.activePrimaryView === PRIMARY_VIEW_BROADCAST
            && this._broadcastAuthoringContext.canCreateBroadcast === true;
    }
    get searchPlaceholder() { return this.showGroups ? 'Buscar por nome do grupo' : 'Buscar por nome, oportunidade ou fases'; }
    get isLoadingGroups() { return this._isLoadingGroups; }
    get hasGroups()       { return !this._isLoadingGroups && this._groups.length > 0; }
    get isEmpty()         { return !this.isLoading && !this.showGroups && this.threads.length === 0; }
    get showList()        { return !this.isLoading && !this.showGroups && this.threads.length > 0; }
    get showPagination()  { return this.showConversationPrimary && this.totalCount > 0 && !this.showGroups; }

    get enrichedGroups() {
        const kw = this.keyword.trim().toLowerCase();
        const viewed = Array.isArray(this.viewedGroupIds) ? this.viewedGroupIds : [];
        return this._groups
            .filter(g => !kw || (g.groupName || '').toLowerCase().includes(kw))
            .sort((a, b) => {
                const aTs = a?.lastMentionAt ? new Date(a.lastMentionAt).getTime() : 0;
                const bTs = b?.lastMentionAt ? new Date(b.lastMentionAt).getTime() : 0;
                return bTs - aTs;
            })
            .map(g => {
                const unread = viewed.includes(g.groupId) ? 0 : (g.unreadMentionCount || 0);
                const countLabel = unread > 99 ? '99+' : String(unread);
                return {
                    ...g,
                    lastMentionAtDisplay: g.lastMentionAt
                        ? new Date(g.lastMentionAt).toLocaleString('pt-BR', {
                            day: '2-digit', month: '2-digit', year: 'numeric',
                            hour: '2-digit', minute: '2-digit'
                          })
                        : '',
                    unreadText:      unread === 1 ? `${countLabel} mensagem` : `${countLabel} mensagens`,
                    unreadAriaLabel: unread === 1 ? '1 mensagem não lida' : `${unread} mensagens não lidas`,
                    showUnreadBadge: unread > 0
                };
            });
    }

    get tabs() {
        const unreadBadge = this._unreadTabCount > 99 ? '99+' : String(this._unreadTabCount);
        const totalGroupUnread = this._groups.reduce((s, g) => s + (g.unreadMentionCount || 0), 0);
        const groupBadge = totalGroupUnread > 99 ? '99+' : String(totalGroupUnread);
        const all = [
            { filter: 'all',    label: 'Todos',     tabClass: this._tabClass('all'),    showBadge: false,                    badgeLabel: '',          badgeClass: 'comm-history__tab-badge' },
            { filter: 'read',   label: 'Lidos',     tabClass: this._tabClass('read'),   showBadge: false,                    badgeLabel: '',          badgeClass: 'comm-history__tab-badge' },
            { filter: 'unread', label: 'Não lidos', tabClass: this._tabClass('unread'), showBadge: this._unreadTabCount > 0, badgeLabel: unreadBadge, badgeClass: 'comm-history__tab-badge' },
            { filter: 'groups', label: 'Grupos',    tabClass: this._tabClass('groups'), showBadge: totalGroupUnread > 0,    badgeLabel: groupBadge,  badgeClass: 'comm-history__tab-badge' },
            {
                filter: PRIMARY_VIEW_BROADCAST,
                label: 'Comunicados',
                tabClass: this._tabClass(PRIMARY_VIEW_BROADCAST),
                showBadge: this.hasBroadcastUnread,
                badgeLabel: this.broadcastBadgeLabel,
                accessibilityLabel: this.broadcastBadgeAccessibilityLabel,
                badgeClass: this.broadcastBadgeClass
            }
        ];
        return all;
    }

    get enrichedThreads() {
        return this.threads.map(t => {
            const displayStage = this._displayStageForThread(t);
            const refs = this._relatedRefsByOpportunityId[t.recordId] || {};
            const relatedRef = this._buildThreadRelatedRef(t, refs);
            return {
                ...t,
                displayStage,
                stageClass:        this._stageClass(displayStage),
                typeLabel:         this._effectiveRecordType(t.recordType, t.hasRepasse) === 'Repasse__c' ? 'Repasse' : 'Oportunidade',
                displayStatusLabel: 'Fase atual:',
                unreadDisplay:     t.unreadCount > 99 ? '99+' : String(t.unreadCount),
                unreadText:      this._unreadText(t.unreadCount),
                unreadAriaLabel: t.unreadCount === 1 ? '1 mensagem não lida' : `${t.unreadCount} mensagens não lidas`,
                showUnreadBadge: t.unreadCount > 0,
                showStatus:      !t.unreadCount && !!t.statusLabel,
                hasStage:        !!displayStage,
                hasRef:          !!t.threadName,
                relatedRefId:            relatedRef.id,
                relatedRefName:          relatedRef.name,
                relatedRefType:          relatedRef.type || null,
                relatedRefObjectApiName: relatedRef.objectApiName,
                showRelatedRef:          !!relatedRef.name,
                isRelatedRefClickable:   !!relatedRef.id,
                lastMessageDisplay:      t.lastMessageAt || 'Conversa não iniciada',
                lastMessageDateClass:    t.lastMessageAt
                    ? 'comm-history__item-date'
                    : 'comm-history__item-date comm-history__item-date--empty'
            };
        });
    }

    _formatQuoteRelatedRefName(quoteName) {
        if (!quoteName) return '';
        return `Cotação-${quoteName}`;
    }

    _buildThreadRelatedRef(threadInfo, refs) {
        if (this._effectiveRecordType(threadInfo?.recordType, threadInfo?.hasRepasse) !== 'Opportunity') {
            return { type: null, id: null, name: '', objectApiName: null };
        }

        if (refs?.resolvedRefId && refs?.resolvedRefName) {
            const isQuote = refs.resolvedRefType === 'quote' || refs.resolvedRefObjectApiName === 'Quote';
            const name = isQuote
                ? this._formatQuoteRelatedRefName(refs.resolvedRefName)
                : refs.resolvedRefName;
            return {
                type: refs.resolvedRefType || null,
                id: refs.resolvedRefId,
                name,
                objectApiName: refs.resolvedRefObjectApiName || null
            };
        }

        const stageType = this._getOpportunityFilterValue(threadInfo);

        // Stage-specific logic with "not found" fallback
        if (stageType === 'opportunity_negociacao') {
            if (refs?.quoteId && refs?.quoteName) {
                return { type: 'quote', id: refs.quoteId, name: this._formatQuoteRelatedRefName(refs.quoteName), objectApiName: 'Quote' };
            }
            return { type: 'not_found', id: null, name: RELATED_REF_NOT_FOUND_LABEL_BY_STAGE[stageType], objectApiName: null };
        }
        if (stageType === 'opportunity_analise_credito') {
            if (refs?.abId && refs?.abName) return { type: 'ab', id: refs.abId, name: refs.abName, objectApiName: 'AprovacaoBancaria__c' };
            if (refs?.arId && refs?.arName) return { type: 'ar', id: refs.arId, name: refs.arName, objectApiName: 'AnaliseFinanceira__c' };
            return { type: 'not_found', id: null, name: RELATED_REF_NOT_FOUND_LABEL_BY_STAGE[stageType], objectApiName: null };
        }
        if (stageType === 'opportunity_analise_renda') {
            if (refs?.abId && refs?.abName) return { type: 'ab', id: refs.abId, name: refs.abName, objectApiName: 'AprovacaoBancaria__c' };
            if (refs?.arId && refs?.arName) return { type: 'ar', id: refs.arId, name: refs.arName, objectApiName: 'AnaliseFinanceira__c' };
            return { type: 'not_found', id: null, name: RELATED_REF_NOT_FOUND_LABEL_BY_STAGE[stageType], objectApiName: null };
        }
        if (stageType === 'opportunity_montagem_pasta') {
            if (refs?.abId && refs?.abName) return { type: 'ab', id: refs.abId, name: refs.abName, objectApiName: 'AprovacaoBancaria__c' };
            if (refs?.arId && refs?.arName) return { type: 'ar', id: refs.arId, name: refs.arName, objectApiName: 'AnaliseFinanceira__c' };
        }

        return { type: null, id: null, name: '', objectApiName: null };
    }

    _normalizeStatusKey(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[̀-ͯ]/g, '')
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' ');
    }

    _getOpportunityFilterValue(threadInfo) {
        const status = this._normalizeStatusKey(threadInfo?.currentStage || threadInfo?.stageName || '');
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

    get totalLabel() {
        return `Total de ${this.totalCount} ${this.totalCount === 1 ? 'item' : 'itens'}`;
    }

    get pageSizeLabel() {
        return `${this.pageSize} / pág.`;
    }

    get paginationItems() {
        const items = [];
        const addPage = page => items.push({
            key: `page-${page}`,
            type: 'page',
            label: String(page),
            page,
            className: page === this.currentPage
                ? 'comm-history__page-number comm-history__page-number--active'
                : 'comm-history__page-number'
        });
        const addEllipsis = key => items.push({
            key,
            type: 'ellipsis',
            label: '...'
        });

        if (this.totalPages <= 7) {
            for (let page = 1; page <= this.totalPages; page++) addPage(page);
            return items;
        }

        addPage(1);

        if (this.currentPage > 3) {
            addEllipsis('ellipsis-left');
        }

        const start = Math.max(2, this.currentPage - 1);
        const end = Math.min(this.totalPages - 1, this.currentPage + 1);
        for (let page = start; page <= end; page++) {
            addPage(page);
        }

        if (this.currentPage < this.totalPages - 2) {
            addEllipsis('ellipsis-right');
        }

        addPage(this.totalPages);
        return items;
    }

    get hasActiveFilter() { return !!(this._etapaFilter || this._stageFilters.length > 0); }

    get filterBtnClass() {
        return this.hasActiveFilter
            ? 'comm-history__filter-btn comm-history__filter-btn--active'
            : 'comm-history__filter-btn';
    }

    get etapaOptions() {
        return [
            { label: 'Oportunidade', value: 'Opportunity', selected: this._etapaFilter === 'Opportunity' },
            { label: 'Repasse',      value: 'Repasse__c',  selected: this._etapaFilter === 'Repasse__c'  }
        ];
    }

    get stageOptions() {
        const source = this._getKeywordEtapaDedupedThreads();
        const stageStats = new Map();
        for (const t of source) {
            const stage = this._displayStageForThread(t);
            if (!stage) continue;
            stageStats.set(stage, (stageStats.get(stage) || 0) + 1);
        }

        return Array.from(stageStats.keys()).map(stage => ({
            label:   stage,
            value:   stage,
            checked: this._stageFilters.includes(stage),
            count:   stageStats.get(stage) || 0
        }));
    }

    get hasStageOptions() { return this.stageOptions.length > 0; }

    get showConversationPrimary() {
        return this.activePrimaryView === PRIMARY_VIEW_CONVERSATIONS;
    }

    get showBroadcastView() {
        return this.activePrimaryView === PRIMARY_VIEW_BROADCAST;
    }

    get showBroadcastImagePreview() {
        return !!this.broadcastImagePreview?.src;
    }

    get broadcastImagePreviewSrc() {
        return this.broadcastImagePreview?.src || '';
    }

    get broadcastImagePreviewFileName() {
        return this.broadcastImagePreview?.fileName || 'Imagem anexada';
    }

    get broadcastImagePreviewAlternativeText() {
        return this.broadcastImagePreview?.alternativeText || 'Imagem anexada';
    }

    get maximizeIcon() {
        return this.isMaximized ? 'utility:contract_alt' : 'utility:expand_alt';
    }

    get maximizeLabel() {
        return this.isMaximized ? 'Restaurar' : 'Expandir';
    }

    _tabClass(filter) {
        const base = 'comm-history__tab';
        if (filter === PRIMARY_VIEW_BROADCAST) {
            return this.activePrimaryView === PRIMARY_VIEW_BROADCAST ? `${base} ${base}--active` : base;
        }
        return this.activePrimaryView === PRIMARY_VIEW_CONVERSATIONS && filter === this.activeFilter
            ? `${base} ${base}--active`
            : base;
    }

    _stageClass(stage) {
        if (!stage) return 'comm-history__badge comm-history__badge--default';
        const s = stage.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
        if (s.includes('cotac'))                                                                                              return 'comm-history__badge comm-history__badge--indigo-soft';
        if (s.includes('apura'))                                                                                              return 'comm-history__badge comm-history__badge--orange';
        if (s.includes('negocia') || s.includes('anali'))                                                                     return 'comm-history__badge comm-history__badge--blue';
        if (s.includes('monta')  || s.includes('pasta'))                                                                      return 'comm-history__badge comm-history__badge--yellow';
        if (s.includes('condicao comercial'))                                                                                 return 'comm-history__badge comm-history__badge--green';
        if (s.includes('aprovad') || s.includes('confor'))                                                                    return 'comm-history__badge comm-history__badge--green';
        if (s.includes('reprovad') || s.includes('cancel'))                                                                   return 'comm-history__badge comm-history__badge--red';
        if (s.includes('aguard') || s.includes('repasse') || s.includes('formu') || s.includes('outro') ||
            s.includes('doss')   || s.includes('pend')    || s.includes('assin') || s.includes('reten') ||
            s.includes('triag'))                                                                                               return 'comm-history__badge comm-history__badge--blue';
        return 'comm-history__badge comm-history__badge--default';
    }

    _unreadText(unreadCount) {
        const countLabel = unreadCount > 99 ? '99+' : String(unreadCount);
        return unreadCount === 1 ? `${countLabel} mensagem` : `${countLabel} mensagens`;
    }
}