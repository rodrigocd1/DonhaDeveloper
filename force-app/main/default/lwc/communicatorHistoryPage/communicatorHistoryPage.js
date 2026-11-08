import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import formFactor from '@salesforce/client/formFactor';
import getThreadDetail                   from '@salesforce/apex/CommunicatorChatController.getThreadDetail';
import getThreadsForRecord               from '@salesforce/apex/CommunicatorChatController.getThreadsForRecord';
import canRestoreViewedThread            from '@salesforce/apex/CommunicatorChatController.canRestoreViewedThread';
import getRecordCurrentStage             from '@salesforce/apex/CommunicatorChatController.getRecordCurrentStage';
import getRepasseMacroPhaseByOppId       from '@salesforce/apex/CommunicatorChatController.getRepasseMacroPhaseByOppId';
import getRepasseIdByOppId               from '@salesforce/apex/CommunicatorChatController.getRepasseIdByOppId';
import ensureRepasseThread               from '@salesforce/apex/CommunicatorChatController.ensureRepasseThread';
import resolveOpportunityId              from '@salesforce/apex/CommunicatorChatController.resolveOpportunityId';
import getOpportunityRelatedRefs         from '@salesforce/apex/CommunicatorChatController.getOpportunityRelatedRefs';
import getRecordName                     from '@salesforce/apex/CommunicatorChatController.getRecordName';
import markThreadAsRead                  from '@salesforce/apex/CommunicatorChatController.markThreadAsRead';
import markThreadAsRecentlyViewed        from '@salesforce/apex/CommunicatorChatController.markThreadAsRecentlyViewed';
import markGroupMentionsAsRead           from '@salesforce/apex/CommunicatorChatController.markGroupMentionsAsRead';
import getSettings                       from '@salesforce/apex/CommunicatorChatController.getSettings';

const DEFAULT_POLL_MS = 6000;
const MIN_POLL_MS     = 3000;
const OPP_CLOSED_STAGE = 'Contrato Assinado - Oppty Ganha';
const CHATTER_TAB_STAGE = 'chatter';
const CHATTER_TAB_LABEL = 'Chatter';

const RELATED_REF_NOT_FOUND_LABEL_BY_STAGE = Object.freeze({
    opportunity_negociacao:      'Não localizada',
    opportunity_analise_renda:   'AR - Não localizada',
    opportunity_analise_credito: 'AR e AB - Não localizadas'
});

// Canonical stage order (matches prototype)
const STAGE_ORDER = [
    'Montagem de Pasta',
    'Apuração de Renda',
    'Análise de Crédito',
    'Negociação',
    'Análise da Condição de Crédito',
    'Aprovação da Condição Comercial',
    'Contrato em Assinatura',
    'Contrato Assinado - Oppty Ganha'
];

const STAGE_VISUAL_LABEL_BY_NAME = Object.freeze({
    'Análise da Condição de Crédito': 'Condição de Crédito',
    'Aprovação da Condição Comercial': 'Condição Comercial',
    'Contrato Assinado - Oppty Ganha': 'Oppty Ganha'
});

// Canonical Repasse macro-phase order — mirrors REPASSE_FILTER_OPTIONS in communicatorChatFloatingButton.js
const REPASSE_STAGE_ORDER = [
    'Aguardando início',
    'Formulário',
    'Conferência de dossiê',
    'Pendências',
    'Assinatura do repasse',
    'Retenção',
    'Triagem',
    'Outros'
];

export default class CommunicatorHistoryPage extends NavigationMixin(LightningElement) {

    @track _inThreadView       = false;
    @track _inGroupView           = false;
    @track _activeGroup           = null;
    @track _activeGroupThreadId   = null;
    @track _groupHighlightMsgId   = null;
    @track _viewedGroupIds        = [];
    @track _showGroupDetailsModal = false;
    @track activeThreadId      = null;
    @track activeRecordName    = '';
    @track activeRecordId      = null;
    @track activeStageName     = '';   // stage currently being VIEWED (changes on tab click)
    @track _currentRecordStage = '';   // current stage for the ACTIVE etapa (switches on etapa change)
    @track _oppCurrentStage    = '';   // Opportunity's live stage (preserved when switching to Repasse)
    @track _repasseCurrentPhase = '';  // current Repasse macro-phase ('' when no Repasse)
    @track activeThreadName    = '';
    @track _recordThreads      = [];
    @track _activeEtapa        = 'Opportunity';
    @track _arName             = null;
    @track _arId               = null;
    @track _abName             = null;
    @track _abId               = null;
    @track _quoteName          = null;
    @track _quoteId            = null;
    @track highlightMessageId  = null;
    @track chatterSearchTerm   = '';
    @track chatterSearchResults = [];
    @track isChatterSearchLoading = false;
    @track isChatterSearchComplete = false;

    /**
     * When set, opens the history page directly in thread view for the given record.
     * Used when embedding inside a modal (bypasses the @wire page-state approach).
     */
    @api
    get opportunityId() { return this._apiOpportunityId; }
    set opportunityId(val) {
        this._apiOpportunityId = val;
        if (val) {
            this._loadedViaApiProp = true;
            this._openRecordHistory(val);
        }
    }

    /**
     * When true the component is embedded inside a modal.
     * Navigation actions dispatch events instead of navigating directly so the
     * modal parent can close itself before navigating.
     */
    @api isModal = false;
    @api initialThreadId = null;

    _pollTimer               = null;
    _pollIntervalMs          = DEFAULT_POLL_MS;
    _hasGroupAccess          = false;
    _isSalesforcePlatformUser = false;
    _initialRecordId         = null;
    _apiOpportunityId        = null;
    _loadedViaApiProp        = false;
    _repasseThreadReturnFallback = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    async connectedCallback() {
        await this._loadConfig();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        // Skip when the component was already seeded via @api opportunityId
        if (this._loadedViaApiProp) return;
        const opportunityId = pageRef?.state?.c__opportunityId;
        if (!opportunityId || opportunityId === this._initialRecordId) return;
        this._initialRecordId = opportunityId;
        this._openRecordHistory(opportunityId);
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    async handleThreadSelected(event) {
        const { threadId, recordId, recordName } = event.detail;

        // Show thread view immediately with the name from the list
        this._inThreadView       = true;
        this.activeThreadId      = threadId;
        this.activeRecordName    = recordName;
        this.activeRecordId      = recordId || null;
        this.activeStageName     = '';
        this.activeThreadName    = '';
        this._recordThreads      = [];
        this._activeEtapa        = 'Opportunity';
        this._repasseCurrentPhase = '';
        this._oppCurrentStage    = '';
        this._repasseThreadReturnFallback = null;
        this.highlightMessageId  = null;
        this._resetChatterSearchState();

        try {
            let detail = null;
            if (threadId) {
                await markThreadAsRead({ threadId });
                detail = await getThreadDetail({ threadId });
            }
            const normalizedRecordId = await this._resolveOpportunityContextRecordId(
                detail?.recordId || recordId || null,
                detail?.recordType || null
            );
            if (normalizedRecordId) {
                const refsPromise = getOpportunityRelatedRefs({ opportunityIds: [normalizedRecordId] });
                const [threads, liveStage, repassePhase, refsByOpp] = await Promise.all([
                    getThreadsForRecord({ recordId: normalizedRecordId }),
                    getRecordCurrentStage({ recordId: normalizedRecordId, objectType: 'Opportunity' }),
                    getRepasseMacroPhaseByOppId({ opportunityId: normalizedRecordId }),
                    refsPromise
                ]);

                this.activeRecordId   = normalizedRecordId;
                this.activeThreadName = detail?.threadName || '';
                if (detail?.recordName) this.activeRecordName = detail.recordName;
                else if (recordName) this.activeRecordName = recordName;
                if (this.activeRecordId && this._isSalesforceId(this.activeRecordName)) {
                    try {
                        const resolvedRecordName = await getRecordName({ recordId: this.activeRecordId });
                        if (resolvedRecordName) this.activeRecordName = resolvedRecordName;
                    } catch (error) {
                        // Keep current header name when lookup fails.
                    }
                }

                this._recordThreads      = await this._ensureThreadPresent(threads || [], threadId, detail);
                this._oppCurrentStage    = liveStage || detail?.stageName || '';
                this._repasseCurrentPhase = repassePhase || '';

                const oppRefs = (refsByOpp && refsByOpp[normalizedRecordId]) || null;
                this._applyRelatedRefs(oppRefs);
                if (this._repasseCurrentPhase || !oppRefs?.resolvedRefId) this._filterRelatedRefsByStage();
                this._applyNotFoundRelatedRefIfNeeded();

                this._applyEtapaAndSwitch();
            } else if (detail) {
                // Fallback for callers that don't provide the record id.
                this.activeRecordId   = detail.recordId  || null;
                this.activeThreadName = detail.threadName || '';
                if (detail.recordName) this.activeRecordName = detail.recordName;
                if (this.activeRecordId && this._isSalesforceId(this.activeRecordName)) {
                    try {
                        const resolvedRecordName = await getRecordName({ recordId: this.activeRecordId });
                        if (resolvedRecordName) this.activeRecordName = resolvedRecordName;
                    } catch (error) {
                        // Keep current header name when lookup fails.
                    }
                }

                if (detail.recordId) {
                // Fetch threads, live stage, Repasse phase and AR ref in parallel
                    const refsPromise = getOpportunityRelatedRefs({ opportunityIds: [detail.recordId] });
                    const [threads, liveStage, repassePhase, refsByOpp] = await Promise.all([
                        getThreadsForRecord({ recordId: detail.recordId }),
                        getRecordCurrentStage({ recordId: detail.recordId, objectType: 'Opportunity' }),
                        getRepasseMacroPhaseByOppId({ opportunityId: detail.recordId }),
                        refsPromise
                    ]);
                    this._recordThreads      = threads || [];
                    this._oppCurrentStage    = liveStage || detail.stageName || '';
                    this._repasseCurrentPhase = repassePhase || '';

                    const oppRefs = (refsByOpp && refsByOpp[detail.recordId]) || null;
                    this._applyRelatedRefs(oppRefs);
                    if (this._repasseCurrentPhase || !oppRefs?.resolvedRefId) this._filterRelatedRefsByStage();
                    this._applyNotFoundRelatedRefIfNeeded();

                    this._applyEtapaAndSwitch();
                } else {
                    // No recordId — fall back to the thread's own stage
                    this._oppCurrentStage    = detail.stageName || '';
                    this._repasseCurrentPhase = '';
                    this._activeEtapa        = 'Opportunity';
                    this._currentRecordStage = this._oppCurrentStage;
                    this.activeStageName     = this._currentRecordStage;
                }
            }

            this._startPolling();
        } catch (e) {
            console.error('communicatorHistoryPage.handleThreadSelected:', e);
        }
    }

    handleBack() {
        this._stopPolling();
        this._inThreadView         = false;
        this.activeThreadId        = null;
        this.activeRecordName      = '';
        this.activeRecordId        = null;
        this.activeStageName       = '';
        this._currentRecordStage   = '';
        this._oppCurrentStage      = '';
        this._repasseCurrentPhase  = '';
        this.activeThreadName      = '';
        this._recordThreads        = [];
        this._activeEtapa          = 'Opportunity';
        this._arName               = null;
        this._arId                 = null;
        this._abName               = null;
        this._abId                 = null;
        this._quoteName            = null;
        this._quoteId              = null;
        this.highlightMessageId    = null;
        this._repasseThreadReturnFallback = null;
        this._resetChatterSearchState();
        this._syncPrimaryViewPolling();
    }

    handleUnreadThreadClick(event) {
        const { threadId } = event.detail;
        const match = this._recordThreads.find(t => t.threadId === threadId);
        if (!match) return;
        const stageName = this._activeEtapa === 'Opportunity'
            ? this._toCanonicalOppStage(match.stageName)
            : match.stageName;
        this._activateStageTab(stageName, threadId);
    }

    handleUnreadLastMessageClick(event) {
        const { threadId } = event.detail;
        const match = this._recordThreads.find(t => t.threadId === threadId);
        if (!match) return;
        const stageName = this._activeEtapa === 'Opportunity'
            ? this._toCanonicalOppStage(match.stageName)
            : match.stageName;
        this._activateStageTab(stageName, threadId);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.template.querySelector('c-communicator-chat-timeline')?.scrollToBottom();
        }, 300);
    }

    handleStageTabClick(event) {
        const stageName = event.currentTarget.dataset.stage;
        const fallbackThreadId = event.currentTarget.dataset.threadId || null;
        this._activateStageTab(stageName, fallbackThreadId);
    }

    handleMobileStageChange(event) {
        const stageName = event.target.value;
        const selectedTab = this.stageTabs.find(tab => tab.stage === stageName);
        const fallbackThreadId = selectedTab ? selectedTab.threadId : null;
        this._activateStageTab(stageName, fallbackThreadId);
    }

    _activateStageTab(stageName, fallbackThreadId) {
        if (!stageName) return;
        if (stageName === CHATTER_TAB_STAGE) {
            this.activeStageName = CHATTER_TAB_STAGE;
            this.highlightMessageId = null;
            return;
        }

        this._resetChatterSearchState();
        const threadId = this._findThreadIdForStage(stageName, fallbackThreadId);
        this.activeStageName = stageName;
        this.activeThreadId = threadId;
        this.highlightMessageId = null;

        if (threadId) {
            markThreadAsRead({ threadId }).catch(console.error);
            markThreadAsRecentlyViewed({ threadId }).catch(() => {});
        }
    }

    _findThreadIdForStage(stageName, fallbackThreadId) {
        const norm = s => (s || '').trim().toLowerCase();
        const match = this._recordThreads.find(t => {
            const canonicalStage = this._activeEtapa === 'Opportunity'
                ? this._toCanonicalOppStage(t.stageName)
                : t.stageName;
            return norm(canonicalStage) === norm(stageName);
        });

        if (match && match.threadId) return match.threadId;
        if (fallbackThreadId) return fallbackThreadId;
        if (norm(stageName) === norm(this.activeStageName)) return this.activeThreadId;
        return null;
    }

    async _ensureThreadPresent(threads, threadId, threadDetail = null) {
        const normalizedThreads = Array.isArray(threads) ? [...threads] : [];
        if (!threadId || normalizedThreads.some(t => t?.threadId === threadId)) {
            return normalizedThreads;
        }

        const detail = threadDetail?.threadId === threadId
            ? threadDetail
            : await getThreadDetail({ threadId });
        if (!detail?.threadId) {
            return normalizedThreads;
        }

        normalizedThreads.push({
            threadId: detail.threadId,
            threadName: detail.threadName || '',
            recordId: detail.recordId || null,
            recordType: detail.recordType || null,
            stageName: detail.stageName || '',
            unreadCount: 0,
            statusLabel: detail.statusLabel || null,
            recordName: detail.recordName || ''
        });
        return normalizedThreads;
    }

    // ─────────────────────────────────────────
    // Group view handlers
    // ─────────────────────────────────────────

    handleGroupSelected(event) {
        this._stopPolling();
        this._inGroupView          = true;
        this._inThreadView         = false;
        this._activeGroup          = event.detail.group;
        this._activeGroupThreadId  = null;
        this._groupHighlightMsgId  = null;
        const groupId = event.detail?.group?.groupId;
        if (groupId) {
            if (!this._viewedGroupIds.includes(groupId)) {
                this._viewedGroupIds = [...this._viewedGroupIds, groupId];
            }
            markGroupMentionsAsRead({ groupId }).catch(console.error);
        }
    }

    handleGroupBack() {
        this._inGroupView         = false;
        this._activeGroup         = null;
        this._activeGroupThreadId = null;
        this._groupHighlightMsgId = null;
        this._syncPrimaryViewPolling();
    }

    handleGroupThreadReady(event) {
        this._activeGroupThreadId = event.detail.threadId;
    }

    handleGroupNavigateMessage(event) {
        this._groupHighlightMsgId = event.detail.messageId;
    }

    handleGroupDetails() {
        this._showGroupDetailsModal = true;
    }

    handleGroupDetailsClose() {
        this._showGroupDetailsModal = false;
    }

    handleGroupUpdated(event) {
        const { groupName } = event.detail;
        if (groupName && this._activeGroup) {
            this._activeGroup = { ...this._activeGroup, groupName };
        }
        this._showGroupDetailsModal = false;
    }

    handleGroupDeleted() {
        this._showGroupDetailsModal = false;
        this._inGroupView           = false;
        this._activeGroup           = null;
        this._activeGroupThreadId   = null;
        this._groupHighlightMsgId   = null;
    }

    // ─────────────────────────────────────────
    // Record navigation
    // ─────────────────────────────────────────

    async handleAccessRecord() {
        if (!this.activeRecordId) return;
        if (this._isSalesforcePlatformUser) {
            try {
                const repasseId = await getRepasseIdByOppId({ opportunityId: this.activeRecordId });
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
                console.error('communicatorHistoryPage.handleAccessRecord:', e);
            }
            return;
        }
        this._navigateToRecord(this.activeRecordId, 'Opportunity');
    }

    handleNavigateToRecord(event) {
        const { recordId, objectType } = event.detail || {};
        if (!recordId) return;
        this._navigateToRecord(recordId, objectType || 'Opportunity');
    }

    handleChatterSearchChange(event) {
        this.chatterSearchTerm = event.detail?.keyword || '';
    }

    handleChatterSearchStateChange(event) {
        this.chatterSearchResults = Array.isArray(event.detail?.results) ? event.detail.results : [];
        this.isChatterSearchLoading = event.detail?.isSearching === true;
        this.isChatterSearchComplete = event.detail?.isComplete === true;
    }

    async handleChatterNavigateToMessage(event) {
        const feedItemId = event.detail?.messageId;
        if (!feedItemId) return;

        const match = (this.chatterSearchResults || []).find((result) => result.Id === feedItemId);
        await this.template.querySelector('c-communicator-chatter-history')?.navigateToFeedItem(feedItemId, {
            expandComments: match?.expandComments === true,
            feedCommentId: match?.feedCommentId || null
        });
    }

    handleChatterFileNavigation(event) {
        event.stopPropagation();

        const contentDocumentId = String(event.detail?.contentDocumentId || '').trim();
        if (!contentDocumentId || !this.canNavigateChatterFiles) {
            this._showChatterFileNavigationError();
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                recordIds: contentDocumentId,
                selectedRecordId: contentDocumentId
            }
        });
    }

    _showChatterFileNavigationError() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Aviso',
            message: 'Nao foi possivel abrir o arquivo agora.',
            variant: 'warning'
        }));
    }

    _navigateToRecord(recordId, objectType) {
        if (this.isModal) {
            this.dispatchEvent(new CustomEvent('navigatetorecord', {
                detail: { recordId, objectType: objectType || 'Opportunity' }
            }));
            return;
        }
        if (this._isOpportunityRecord(recordId, objectType) && this._isBrokerCommunityContext()) {
            this._navigateToBrokerCommunityOpportunity(recordId);
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: objectType || 'Opportunity',
                actionName:    'view'
            }
        });
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

    _navigateToBrokerCommunityOpportunity(recordId) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        window.open(`${normalizedBasePath}/corretores/s/opportunity/${recordId}`, '_blank');
    }

    handleAccessAr() {
        this._navigateToRelatedReference('ar', this._arId, this._arName, 'AnaliseFinanceira__c');
    }

    handleAccessAb() {
        this._navigateToRelatedReference('ab', this._abId, this._abName, 'AprovacaoBancaria__c');
    }

    handleAccessQuote() {
        this._navigateToRelatedReference('quote', this._quoteId, this.activeQuoteName, 'Quote');
    }

    _navigateToRelatedReference(type, recordId, recordName, objectApiName) {
        if (!recordId) return;
        const normalizedType = String(type || '').toLowerCase();

        if (this._isBrokerCommunityContext()
            && this._openBrokerCommunityRelatedRecord(normalizedType, recordId, recordName)) {
            return;
        }

        if (this.isModal && normalizedType === 'ar') {
            this.dispatchEvent(new CustomEvent('navigatetoar', {
                detail: { arId: recordId }
            }));
            return;
        }

        this._navigateToRecord(recordId, objectApiName || this._objectApiNameByRelatedRefType(normalizedType));
    }

    _openBrokerCommunityRelatedRecord(type, recordId, recordName) {
        if (type === 'ar' || type === 'analise_credito') {
            this._openBrokerCommunityAnaliseFinanceira(recordId, recordName);
            return true;
        }
        if (type === 'ab') {
            this._openBrokerCommunityDetail(recordId);
            return true;
        }
        if (type === 'quote') {
            this._openBrokerCommunityQuote(recordId, recordName);
            return true;
        }
        return false;
    }

    _objectApiNameByRelatedRefType(type) {
        if (type === 'ab') return 'AprovacaoBancaria__c';
        if (type === 'quote') return 'Quote';
        return 'AnaliseFinanceira__c';
    }

    _openBrokerCommunityAnaliseFinanceira(recordId, recordName) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        const recordSlug = this._normalizeAnaliseFinanceiraSlug(recordName);
        const slugSegment = recordSlug ? `/${recordSlug}` : '';
        window.open(`${normalizedBasePath}/corretores/s/analisefinanceira/${recordId}${slugSegment}`, '_blank');
    }

    _openBrokerCommunityQuote(recordId, recordName) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        const recordSlug = this._normalizeCommunityQuoteSlug(recordName);
        const slugSegment = recordSlug ? `/${encodeURIComponent(recordSlug)}` : '';
        window.open(`${normalizedBasePath}/corretores/s/quote/${recordId}${slugSegment}`, '_blank');
    }

    _openBrokerCommunityDetail(recordId) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        window.open(`${normalizedBasePath}/corretores/s/detail/${recordId}`, '_blank');
    }

    _normalizeAnaliseFinanceiraSlug(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .replace(/[^a-z0-9]/g, '');
    }

    _normalizeCommunityQuoteSlug(value) {
        return String(value || '')
            .normalize('NFC')
            .trim()
            .toLowerCase()
            .replace(/[^0-9a-z\u00c0-\u024f]+/g, '-')
            .replace(/-+/g, '-')
            .replace(/^-|-$/g, '');
    }

    _normalizeBrokerCommunityBasePath() {
        const pathname = String(window.location?.pathname || '');
        const basePath = pathname.includes('/s/') ? pathname.split('/s/')[0] : pathname;
        return basePath
            .replace(/\/kanban.*$/i, '')
            .replace(/\/+$/, '')
            .replace(/\/corretores$/i, '');
    }

    handleMessageSent() {
        this.template.querySelector('c-communicator-chat-timeline')?.refresh();
        this.template.querySelector('c-communicator-chat-timeline')?.scrollToBottom();
    }

    handleNavigateToMessage(event) {
        const { messageId, threadId } = event?.detail || {};
        if (!messageId) return;

        this.highlightMessageId = messageId;

        const isSameThread = !threadId || threadId === this.activeThreadId;
        if (isSameThread) {
            this.template.querySelector('c-communicator-chat-timeline')?.navigateToMessage(messageId);
        } else {
            const match = this._recordThreads.find(t => t.threadId === threadId);
            if (match) {
                // Use canonical label so the correct tab gets highlighted
                this.activeStageName = this._activeEtapa === 'Opportunity'
                    ? this._toCanonicalOppStage(match.stageName)
                    : (match.stageName || '');
                this.activeThreadId  = threadId;
                markThreadAsRead({ threadId }).catch(console.error);
            }
        }
    }

    async handleEtapaChange(event) {
        const keepChatterActive = this.isChatterTabActive;
        const nextEtapa = event.target.value;
        if (this._activeEtapa === 'Repasse__c' && nextEtapa === 'Opportunity') {
            this._captureRepasseThreadReturnFallback();
        }
        this._activeEtapa = nextEtapa;
        // Point _currentRecordStage at the correct stage for the selected etapa,
        // then jump the tab carousel to that stage.
        this._currentRecordStage = this._activeEtapa === 'Repasse__c'
            ? this._repasseCurrentPhase
            : this._oppCurrentStage;
        this._switchToCurrentStage();
        this._restoreChatterTabIfNeeded(keepChatterActive);
        if (this._activeEtapa === 'Repasse__c' && !this.activeThreadId) {
            await this._restoreRepasseThreadReturnFallback();
            this._restoreChatterTabIfNeeded(keepChatterActive);
        }
    }

    _resetChatterSearchState() {
        this.chatterSearchTerm = '';
        this.chatterSearchResults = [];
        this.isChatterSearchLoading = false;
        this.isChatterSearchComplete = false;
    }

    async _openRecordHistory(recordId) {
        if (!recordId) return;

        const normalizedRecordId = await this._resolveOpportunityContextRecordId(recordId, null);
        if (!normalizedRecordId) return;

        this._stopPolling();
        this._inThreadView        = true;
        this.activeThreadId       = null;
        this.activeRecordName     = '';
        this.activeRecordId       = normalizedRecordId;
        this.activeStageName      = '';
        this._currentRecordStage  = '';
        this._oppCurrentStage     = '';
        this._repasseCurrentPhase = '';
        this.activeThreadName     = '';
        this._recordThreads       = [];
        this._activeEtapa         = 'Opportunity';
        this._arName              = null;
        this._arId                = null;
        this._abName              = null;
        this._abId                = null;
        this._quoteName           = null;
        this._quoteId             = null;
        this.highlightMessageId   = null;
        this._repasseThreadReturnFallback = null;
        this._resetChatterSearchState();

        try {
            if (this.initialThreadId) {
                await markThreadAsRead({ threadId: this.initialThreadId });
            }
            const initialThreadDetailPromise = this.initialThreadId
                ? getThreadDetail({ threadId: this.initialThreadId })
                : Promise.resolve(null);
            const [threads, liveStage, repassePhase, refsByOpp, recordName, initialThreadDetail] = await Promise.all([
                getThreadsForRecord({ recordId: normalizedRecordId }),
                getRecordCurrentStage({ recordId: normalizedRecordId, objectType: 'Opportunity' }),
                getRepasseMacroPhaseByOppId({ opportunityId: normalizedRecordId }),
                getOpportunityRelatedRefs({ opportunityIds: [normalizedRecordId] }),
                getRecordName({ recordId: normalizedRecordId }),
                initialThreadDetailPromise
            ]);

            this._recordThreads       = await this._ensureThreadPresent(threads || [], this.initialThreadId, initialThreadDetail);
            // When the user lacks Opportunity sharing access, getRecordCurrentStage returns ''.
            // Fall back to the most recent thread's stage (last in ASC order) so the correct tab opens.
            const _fallbackOppStage   = this._recordThreads.length > 0
                ? (this._recordThreads[this._recordThreads.length - 1]?.stageName || '')
                : '';
            this._oppCurrentStage     = liveStage || _fallbackOppStage;
            this._repasseCurrentPhase = repassePhase || '';
            this.activeRecordName     = recordName || initialThreadDetail?.recordName || '';

            if (this.initialThreadId && this._recordThreads.length === 0) {
                this.handleBack();
                return;
            }

            const oppRefs = (refsByOpp && refsByOpp[normalizedRecordId]) || null;
            this._applyRelatedRefs(oppRefs);
            if (this._repasseCurrentPhase || !oppRefs?.resolvedRefId) this._filterRelatedRefsByStage();
            this._applyNotFoundRelatedRefIfNeeded();

            this._applyEtapaAndSwitch();

            if (this.initialThreadId) {
                const target = this._recordThreads.find(t => t.threadId === this.initialThreadId);
                if (target) {
                    const label = this._activeEtapa === 'Opportunity'
                        ? this._toCanonicalOppStage(target.stageName)
                        : target.stageName;
                    this.activeStageName = label;
                    this.activeThreadId  = target.threadId;
                    markThreadAsRead({ threadId: target.threadId }).catch(console.error);
                    markThreadAsRecentlyViewed({ threadId: target.threadId }).catch(() => {});
                }
            }

            this._startPolling();
        } catch (e) {
            console.error('communicatorHistoryPage._openRecordHistory:', e);
            this.handleBack();
        }
    }

    // ─────────────────────────────────────────
    // Config & Polling
    // ─────────────────────────────────────────

    async _loadConfig() {
        try {
            const settings = await getSettings();
            if (settings.pollingIntervalMs >= MIN_POLL_MS) {
                this._pollIntervalMs = settings.pollingIntervalMs;
            }
            this._hasGroupAccess           = settings.hasGroupAccess === true;
            this._isSalesforcePlatformUser = settings.isSalesforcePlatformUser === true;
        } catch (e) {
            // Keep default on failure
        }
    }

    /**
     * Sets the active etapa + _currentRecordStage, then switches to the current stage tab.
     * Called on initial open and when Repasse phase data arrives.
     */
    _applyEtapaAndSwitch() {
        if (this._repasseCurrentPhase) {
            this._activeEtapa        = 'Repasse__c';
            this._currentRecordStage = this._repasseCurrentPhase;
        } else {
            this._activeEtapa        = 'Opportunity';
            this._currentRecordStage = this._oppCurrentStage;
        }

        if (this._currentRecordStage) {
            this._switchToCurrentStage();
            // If Repasse phase has no thread yet, create one so the message input appears
            if (this._activeEtapa === 'Repasse__c' && !this.activeThreadId && this.activeRecordId) {
                ensureRepasseThread({
                    opportunityId: this.activeRecordId,
                    macroPhase:    this._repasseCurrentPhase
                }).then(threadId => {
                    if (!threadId) return;
                    const norm = s => (s || '').trim().toLowerCase();
                    const alreadyIn = this._recordThreads.some(t => t.threadId === threadId);
                    if (!alreadyIn) {
                        this._recordThreads = [...this._recordThreads, {
                            threadId,
                            stageName:    this._repasseCurrentPhase,
                            unreadCount:  0,
                            threadName:   ''
                        }];
                    }
                    this.activeThreadId = threadId;
                    markThreadAsRead({ threadId }).catch(console.error);
                }).catch(console.error);
            }
        } else if (this._recordThreads.length > 0) {
            const firstThread = this._recordThreads[0];
            this.activeStageName  = firstThread.stageName || '';
            this.activeThreadId   = firstThread.threadId || null;
            this.activeThreadName = firstThread.threadName || '';
            if (this.activeThreadId) {
                markThreadAsRead({ threadId: this.activeThreadId }).catch(console.error);
            }
        }
    }

    /**
     * Points activeStageName and activeThreadId to the record's CURRENT stage.
     * If there is already a thread for that stage it loads it; otherwise shows empty state.
     * Does NOT override a tab the user has MANUALLY chosen — only call this when the
     * live stage changes or on first open.
     */
    _switchToCurrentStage() {
        const norm           = s => (s || '').trim().toLowerCase();
        const stage          = this._currentRecordStage;
        const canonicalStage = this._activeEtapa === 'Opportunity'
            ? this._toCanonicalOppStage(stage)
            : stage;
        const match = this._recordThreads.find(t => {
            const tCanon = this._activeEtapa === 'Opportunity'
                ? this._toCanonicalOppStage(t.stageName)
                : t.stageName;
            return norm(tCanon) === norm(canonicalStage);
        });
        this.activeStageName = canonicalStage;
        this.activeThreadId  = match ? match.threadId : null;
        if (match) {
            markThreadAsRead({ threadId: match.threadId }).catch(console.error);
        }
    }

    _restoreChatterTabIfNeeded(keepChatterActive) {
        if (keepChatterActive && this.hasOpportunityContext) {
            this.activeStageName = CHATTER_TAB_STAGE;
        }
    }

    _captureRepasseThreadReturnFallback() {
        if (!this.activeRecordId || !this.activeStageName || !this.activeThreadId) return;
        this._repasseThreadReturnFallback = {
            recordId: this.activeRecordId,
            stageName: this.activeStageName,
            threadId: this.activeThreadId
        };
    }

    async _restoreRepasseThreadReturnFallback() {
        const fallback = this._repasseThreadReturnFallback;
        if (!fallback) return false;
        if (fallback.recordId !== this.activeRecordId) {
            this._repasseThreadReturnFallback = null;
            return false;
        }

        let canRestore = false;
        try {
            canRestore = await canRestoreViewedThread({
                threadId: fallback.threadId,
                expectedRecordId: fallback.recordId
            });
        } catch (error) {
            canRestore = false;
        }
        if (
            !canRestore
            || fallback.recordId !== this.activeRecordId
            || this._activeEtapa !== 'Repasse__c'
            || this.activeThreadId
        ) {
            this._repasseThreadReturnFallback = null;
            return false;
        }

        const hasFallbackThread = this._recordThreads.some(t => t.threadId === fallback.threadId);
        if (!hasFallbackThread) {
            // Platform users can open a Repasse thread that is temporarily absent from
            // the refreshed thread list; keep the already-open thread restorable when
            // returning from an empty Opportunity etapa.
            this._recordThreads = [
                ...this._recordThreads,
                {
                    threadId: fallback.threadId,
                    stageName: fallback.stageName,
                    recordId: fallback.recordId,
                    recordType: 'Opportunity',
                    unreadCount: 0,
                    threadName: ''
                }
            ];
        }

        this.activeStageName = fallback.stageName;
        this.activeThreadId = fallback.threadId;
        this.highlightMessageId = null;
        this._repasseThreadReturnFallback = null;
        markThreadAsRead({ threadId: fallback.threadId }).catch(console.error);
        return true;
    }

    /**
     * Maps a raw Salesforce Opportunity StageName to the canonical STAGE_ORDER label.
     * Mirrors the grouping logic in _getOpportunityFilterValue (communicatorChatFloatingButton).
     */
    _toCanonicalOppStage(stageName) {
        const s = (stageName || '')
            .normalize('NFD').replace(/[̀-ͯ]/g, '')
            .toLowerCase().trim().replace(/\s+/g, ' ');
        if (s.includes('montagem'))                                              return 'Montagem de Pasta';
        if (s.includes('analise de renda') || s.includes('apuracao de renda'))  return 'Apuração de Renda';
        if (s.includes('analise de credito') || s.includes('cotacao') ||
            s.includes('cotacoes') || s.includes('aprovacao bancaria'))         return 'Análise de Crédito';
        if (s.includes('negoci'))                                                return 'Negociação';
        if (s.includes('condicao credito') ||
            s.includes('condicao de credito') ||
            s.includes('aprovacao da condicao credito'))                         return 'Análise da Condição de Crédito';
        if (s.includes('condicao comercial') ||
            (s.includes('comercial') && !s.includes('credito')))                return 'Aprovação da Condição Comercial';
        if (s.includes('contrato') &&
            !s.includes('assinado') && !s.includes('ganha'))                    return 'Contrato em Assinatura';
        if (s.includes('assinado') || s.includes('ganha') ||
            s.includes('desembolsado'))                                          return 'Contrato Assinado - Oppty Ganha';
        return stageName || '';
    }

    _startPolling() {
        this._stopPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => {
            this.template.querySelector('c-communicator-chat-timeline')?.refresh();
            if (this.activeRecordId) {
                Promise.all([
                    getThreadsForRecord({ recordId: this.activeRecordId }),
                    getRecordCurrentStage({ recordId: this.activeRecordId, objectType: 'Opportunity' }),
                    getRepasseMacroPhaseByOppId({ opportunityId: this.activeRecordId })
                ]).then(([threads, liveStage, repassePhase]) => {
                    this._recordThreads       = threads || [];
                    // Preserve existing _oppCurrentStage when liveStage is empty (user lacks Opp sharing access).
                    this._oppCurrentStage     = liveStage || this._oppCurrentStage;
                    this._repasseCurrentPhase = repassePhase || '';

                    const norm             = s => (s || '').trim().toLowerCase();
                    const newCurrentStage  = this._activeEtapa === 'Repasse__c'
                        ? this._repasseCurrentPhase
                        : this._oppCurrentStage;

                    if (norm(newCurrentStage) !== norm(this._currentRecordStage)) {
                        const keepChatterActive = this.isChatterTabActive;
                        this._currentRecordStage = newCurrentStage;
                        this._switchToCurrentStage();
                        this._restoreChatterTabIfNeeded(keepChatterActive);
                    } else {
                        // Stage unchanged — restore active thread if user hadn't selected one yet
                        if (!this.activeThreadId && this.activeStageName) {
                            const match = this._recordThreads.find(
                                t => norm(t.stageName) === norm(this.activeStageName)
                            );
                            if (match) {
                                this.activeThreadId = match.threadId;
                                markThreadAsRead({ threadId: match.threadId }).catch(console.error);
                            }
                        }
                    }
                }).catch(console.error);
            }
        }, this._pollIntervalMs);
    }

    _syncPrimaryViewPolling() {
        if (this._inThreadView) {
            this._startPolling();
            return;
        }
        this._stopPolling();
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get etapaOptions() {
        return [
            { label: 'Oportunidade', value: 'Opportunity', selected: this._activeEtapa === 'Opportunity' },
            { label: 'Repasse',      value: 'Repasse__c',  selected: this._activeEtapa === 'Repasse__c'  }
        ];
    }

    get isMobileExperience()    { return formFactor === 'Small' && !this.isModal; }
    get showGroupDetailsModal() { return this._showGroupDetailsModal; }
    get showList()              { return !this._inThreadView && !this._inGroupView; }
    get showThreadView()        { return this._inThreadView; }
    get showGroupView()         { return this._inGroupView; }
    get hasGroupAccess()    { return this._hasGroupAccess; }
    // Header aparece nas views de thread/grupo em qualquer contexto (modal e Experience)
    // (na list view o communicatorChatHistory já exibe o próprio header)
    get showPageHeader()    { return this._inThreadView || this._inGroupView; }
    get hasOpportunityContext() {
        return this._inThreadView
            && typeof this.activeRecordId === 'string'
            && this.activeRecordId.startsWith('006');
    }

    get isChatterTabActive() {
        return this.activeStageName === CHATTER_TAB_STAGE;
    }

    get showChatterHistory() {
        return this.hasOpportunityContext && !!this.chatterHistoryThreadId && this.isChatterTabActive;
    }

    get chatterHistoryThreadId() {
        if (this.activeThreadId) return this.activeThreadId;
        const fallbackThread = (this._recordThreads || []).find(thread => !!thread?.threadId);
        return fallbackThread?.threadId || null;
    }

    get canNavigateChatterFiles() {
        return !this._isBrokerCommunityContext();
    }

    get showTimeline()      { return this._inThreadView && !this.isChatterTabActive && !!this.activeThreadId; }
    get showEmptyStage()    { return this._inThreadView && !this.isChatterTabActive && !this.activeThreadId; }
    get showAr()            { return !!this._arName && !this._abName && !this._quoteName; }
    get activeArName()      { return this._arName; }
    get isArClickable()     { return !!this._arId; }
    get showAb()            { return !!this._abName && !this._quoteName; }
    get activeAbName()      { return this._abName; }
    get isAbClickable()     { return !!this._abId; }
    get showQuote()         { return !!this._quoteName; }
    get activeQuoteName()   { return this._formatQuoteRelatedRefName(this._quoteName); }
    get isQuoteClickable()  { return !!this._quoteId; }

    /**
     * Show message input only when the viewed stage matches the CURRENT stage of the active etapa.
     * Opportunity tabs are read-only when Repasse already exists.
     */
    get showMessageInput() {
        if (!this._inThreadView || !this.activeThreadId) return false;
        if (this._activeEtapa === 'Opportunity' && this.isOpportunityClosedForMessaging) return false;
        const norm            = s => (s || '').trim().toLowerCase();
        const currentForEtapa = this._activeEtapa === 'Repasse__c'
            ? this._repasseCurrentPhase
            : this._oppCurrentStage;
        // Canonicalize so "Contrato Assinado - Oppty Ganha" matches tab "Oportunidade ganha"
        const canonicalCurrent = this._activeEtapa === 'Opportunity'
            ? this._toCanonicalOppStage(currentForEtapa)
            : currentForEtapa;
        return norm(this.activeStageName) === norm(canonicalCurrent);
    }

    get isOpportunityClosedForMessaging() {
        const norm = s => (s || '').trim().toLowerCase();
        return norm(this._oppCurrentStage) === norm(OPP_CLOSED_STAGE);
    }

    /** The actual current stage of the record — shown in the header badge. */
    get currentRecordStageName() { return this._currentRecordStage; }

    get accessRecordLabel() {
        return this._isSalesforcePlatformUser ? 'Acessar Repasse' : 'Acessar oportunidade';
    }

    get currentRecordTypeLabel() {
        return this._activeEtapa === 'Opportunity' ? 'Oportunidade' : 'Repasse';
    }

    get currentStageBadgeClass() {
        return this._stageBadgeClass(this._currentRecordStage);
    }

    get activeStageBadgeClass() {
        return this._stageBadgeClass(this.activeStageName);
    }

    _stageBadgeClass(stage) {
        const s = (stage || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
        // Opportunity stages — exact match, mesmo padrão de cores do communicatorChatFloatingButton
        if (s === 'montagem de pasta')               return 'comm-hpage__badge comm-hpage__badge--yellow';
        if (s === 'apuracao de renda')               return 'comm-hpage__badge comm-hpage__badge--orange';
        if (s === 'analise de credito')              return 'comm-hpage__badge comm-hpage__badge--blue';
        if (s === 'negociacao')                      return 'comm-hpage__badge comm-hpage__badge--blue';
        if (s === 'analise da condicao de credito')  return 'comm-hpage__badge comm-hpage__badge--blue';
        if (s === 'aprovacao da condicao comercial') return 'comm-hpage__badge comm-hpage__badge--green';
        if (s === 'contrato em assinatura')          return 'comm-hpage__badge comm-hpage__badge--blue';
        if (s === 'contrato assinado - oppty ganha') return 'comm-hpage__badge comm-hpage__badge--green';
        // Repasse stages — includes-based
        if (s.includes('cotac'))                                                                                              return 'comm-hpage__badge comm-hpage__badge--indigo-soft';
        if (s.includes('apura'))                                                                                              return 'comm-hpage__badge comm-hpage__badge--orange';
        if (s.includes('negocia') || s.includes('anali'))                                                                     return 'comm-hpage__badge comm-hpage__badge--blue';
        if (s.includes('monta')  || s.includes('pasta'))                                                                      return 'comm-hpage__badge comm-hpage__badge--yellow';
        if (s.includes('aprovad') || s.includes('confor'))                                                                    return 'comm-hpage__badge comm-hpage__badge--green';
        if (s.includes('reprovad') || s.includes('cancel'))                                                                   return 'comm-hpage__badge comm-hpage__badge--red';
        if (s.includes('aguard') || s.includes('repasse') || s.includes('formu') || s.includes('outro') ||
            s.includes('doss')   || s.includes('pend')    || s.includes('assin') || s.includes('reten') ||
            s.includes('triag'))                                                                                               return 'comm-hpage__badge comm-hpage__badge--blue';
        return 'comm-hpage__badge comm-hpage__badge--default';
    }

    get allThreadIds() {
        return this._recordThreads.map(t => t.threadId).filter(Boolean);
    }

    get stageByThread() {
        return this._recordThreads.reduce((acc, t) => {
            if (t.threadId) acc[t.threadId] = t.stageName || '';
            return acc;
        }, {});
    }

    get mobileStageOptions() {
        return this.stageTabs.map(tab => {
            const badgeSuffix = tab.showBadge ? ` (${tab.badgeLabel})` : '';
            return {
                label: `${tab.label}${badgeSuffix}`,
                value: tab.stage,
                selected: tab.stage === this.activeStageName
            };
        });
    }

    get stageTabs() {
        const norm = s => (s || '').trim().toLowerCase();

        // Build canonical-label → { threadId, unreadCount } map from sibling threads.
        // Opportunity threads use _toCanonicalOppStage so that raw SF stage names like
        // "Contrato Assinado - Oppty Ganha" resolve to the STAGE_ORDER label "Oportunidade ganha".
        const dataByNorm = {};
        for (const t of this._recordThreads) {
            if (!t.stageName) continue;
            const canonLabel = this._activeEtapa === 'Opportunity'
                ? this._toCanonicalOppStage(t.stageName)
                : t.stageName;
            const key = norm(canonLabel);
            if (!dataByNorm[key]) {
                dataByNorm[key] = {
                    threadId:    t.threadId,
                    unreadCount: t.unreadCount || 0,
                    label:       canonLabel
                };
            }
        }

        // Ensure active stage is always present before siblings finish loading
        const activeNorm = norm(this.activeStageName);
        if (activeNorm && !dataByNorm[activeNorm]) {
            dataByNorm[activeNorm] = {
                threadId:    this.activeThreadId,
                unreadCount: 0,
                label:       this.activeStageName
            };
        }

        // Opportunity → canonical hardcoded order (all 8 tabs, even empty ones)
        // Repasse     → canonical 7 macro-phase order (all 7 tabs, even empty ones)
        const stageOrder = this._activeEtapa === 'Opportunity'
            ? STAGE_ORDER
            : REPASSE_STAGE_ORDER;

        const tabs = stageOrder.map(stage => {
            const data = dataByNorm[norm(stage)] || { threadId: null, unreadCount: 0 };
            return this._buildTab(stage, data);
        });

        if (this.hasOpportunityContext) {
            tabs.push(this._buildChatterTab());
        }

        return tabs;
    }

    _buildTab(stage, data) {
        const norm       = s => (s || '').trim().toLowerCase();
        const isActive   = norm(stage) === norm(this.activeStageName);
        const badgeCount = data.unreadCount || 0;
        return {
            label:      this._formatStageTabLabel(stage),
            stage,
            threadId:   data.threadId,
            tabClass:   isActive ? 'comm-hpage__tab comm-hpage__tab--active' : 'comm-hpage__tab',
            showBadge:  badgeCount > 0,
            badgeLabel: badgeCount > 9 ? '9+' : String(badgeCount)
        };
    }

    _buildChatterTab() {
        return {
            label: CHATTER_TAB_LABEL,
            stage: CHATTER_TAB_STAGE,
            threadId: null,
            tabClass: this.isChatterTabActive ? 'comm-hpage__tab comm-hpage__tab--active' : 'comm-hpage__tab',
            showBadge: false,
            badgeLabel: ''
        };
    }

    _formatStageTabLabel(stage) {
        return STAGE_VISUAL_LABEL_BY_NAME[stage] || stage;
    }

    _formatQuoteRelatedRefName(quoteName) {
        if (!quoteName) return '';
        return `Cotação - ${quoteName}`;
    }

    _applyRelatedRefs(refs) {
        this._arName = null;
        this._arId = null;
        this._abName = null;
        this._abId = null;
        this._quoteName = null;
        this._quoteId = null;

        if (refs?.resolvedRefId && refs?.resolvedRefName) {
            if (refs.resolvedRefType === 'ab') {
                this._abId = refs.resolvedRefId;
                this._abName = refs.resolvedRefName;
                return;
            }
            if (refs.resolvedRefType === 'quote') {
                this._quoteId = refs.resolvedRefId;
                this._quoteName = refs.resolvedRefName;
                return;
            }
            this._arId = refs.resolvedRefId;
            this._arName = refs.resolvedRefName;
            return;
        }

        this._arName = refs?.arName || null;
        this._arId = refs?.arId || null;
        this._abName = refs?.abName || null;
        this._abId = refs?.abId || null;
        this._quoteName = refs?.quoteName || null;
        this._quoteId = refs?.quoteId || null;
    }

    _filterRelatedRefsByStage() {
        if (this._repasseCurrentPhase) {
            this._arName    = null;
            this._arId      = null;
            this._abName    = null;
            this._abId      = null;
            this._quoteName = null;
            this._quoteId   = null;
            return;
        }

        const stageType = this._getHistoryOpportunityFilterValue(this._oppCurrentStage);
        if (stageType === 'opportunity_negociacao') {
            this._arName    = null;
            this._arId      = null;
            this._abName    = null;
            this._abId      = null;
        } else if (
            stageType === 'opportunity_analise_credito' ||
            stageType === 'opportunity_montagem_pasta'  ||
            stageType === 'opportunity_analise_renda'
        ) {
            this._quoteName = null;
            this._quoteId   = null;
        } else {
            this._arName    = null;
            this._arId      = null;
            this._abName    = null;
            this._abId      = null;
            this._quoteName = null;
            this._quoteId   = null;
        }
    }

    _applyNotFoundRelatedRefIfNeeded() {
        if (this._repasseCurrentPhase) return;
        const stageType = this._getHistoryOpportunityFilterValue(this._oppCurrentStage);
        const notFoundLabel = RELATED_REF_NOT_FOUND_LABEL_BY_STAGE[stageType];
        if (!notFoundLabel) return;

        if (stageType === 'opportunity_negociacao') {
            if (this._quoteName) return;
            this._quoteName = notFoundLabel;
            this._quoteId = null;
        } else {
            if (this._arName || this._abName) return;
            this._arName = notFoundLabel;
            this._arId = null;
        }
    }

    _normalizeHistoryStatusKey(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[̀-ͯ]/g, '')
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' ');
    }

    _getHistoryOpportunityFilterValue(stageName) {
        const status = this._normalizeHistoryStatusKey(stageName);
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

    async _resolveOpportunityContextRecordId(recordId, objectApiName = null) {
        const normalizedRecordId = String(recordId || '').trim();
        if (!normalizedRecordId) {
            return null;
        }
        if (normalizedRecordId.startsWith('006')) {
            return normalizedRecordId;
        }

        try {
            return await resolveOpportunityId({
                recordId: normalizedRecordId,
                objectApiName: objectApiName || null
            });
        } catch (error) {
            return normalizedRecordId;
        }
    }

    _isSalesforceId(value) {
        return /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(String(value || '').trim());
    }
}