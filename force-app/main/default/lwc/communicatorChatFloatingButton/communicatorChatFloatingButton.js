import { LightningElement, api, track, wire }  from 'lwc';
import { NavigationMixin }          from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { isSalesforceMobileApp, buildDisabledFeatureToast, SALESFORCE_APP_DISABLED_MESSAGE } from 'c/communicatorEnvironment';
import { EnclosingUtilityId, minimize } from 'lightning/platformUtilityBarApi';
import USER_ID from '@salesforce/user/Id';
import {
    connect as connectSocket,
    acquire as acquireSocket,
    release as releaseSocket,
    on as onSocket,
    isConnected as isSocketConnected,
    getUsersConnectionStatus
} from 'c/communicatorSocketService';
import getGroupsWithStats           from '@salesforce/apex/CommunicatorChatController.getGroupsWithStats';
import markGroupMentionsAsRead      from '@salesforce/apex/CommunicatorChatController.markGroupMentionsAsRead';
import getOrCreateThread            from '@salesforce/apex/CommunicatorChatController.getOrCreateThread';
import getUnreadCount               from '@salesforce/apex/CommunicatorChatController.getUnreadCount';
import markThreadAsRead             from '@salesforce/apex/CommunicatorChatController.markThreadAsRead';
import getSettings                  from '@salesforce/apex/CommunicatorChatController.getSettings';
import getOpportunityChatList       from '@salesforce/apex/CommunicatorChatController.getOpportunityChatList';
import getOpportunityChatCount      from '@salesforce/apex/CommunicatorChatController.getOpportunityChatCount';
import getOpportunityUnreadMessageTotal from '@salesforce/apex/CommunicatorChatController.getOpportunityUnreadMessageTotal';
import getBroadcastUnreadTotal         from '@salesforce/apex/CommunicatorChatController.getBroadcastUnreadTotal';
import getGlobalUnreadCount           from '@salesforce/apex/CommunicatorChatController.getGlobalUnreadCount';
import getThreadPresenceOverrides   from '@salesforce/apex/CommunicatorChatController.getThreadPresenceOverrides';
import getThreadsForRecord          from '@salesforce/apex/CommunicatorChatController.getThreadsForRecord';
import getThreadHistoryParticipantIdsAcrossThreads from '@salesforce/apex/CommunicatorChatController.getThreadHistoryParticipantIdsAcrossThreads';
import getRepasseMacroPhaseByOppId  from '@salesforce/apex/CommunicatorChatController.getRepasseMacroPhaseByOppId';
import ensureRepasseThread          from '@salesforce/apex/CommunicatorChatController.ensureRepasseThread';
import getRecordName                from '@salesforce/apex/CommunicatorChatController.getRecordName';
import getRecordCurrentStage        from '@salesforce/apex/CommunicatorChatController.getRecordCurrentStage';
import getOpportunityRelatedRefs    from '@salesforce/apex/CommunicatorChatController.getOpportunityRelatedRefs';
import resolveOpportunityAccessRedirect from '@salesforce/apex/CommunicatorChatController.resolveOpportunityAccessRedirect';
import getRepasseIdByOppId          from '@salesforce/apex/CommunicatorChatController.getRepasseIdByOppId';
import reconcileSocketMessage       from '@salesforce/apex/CommunicatorChatController.reconcileSocketMessage';
import getRecentlyViewedThreads     from '@salesforce/apex/CommunicatorChatController.getRecentlyViewedThreads';
import getRecentlyViewedThreadCards from '@salesforce/apex/CommunicatorChatController.getRecentlyViewedThreadCards';
import markThreadAsRecentlyViewed   from '@salesforce/apex/CommunicatorChatController.markThreadAsRecentlyViewed';

const MAX_RECENT         = 5;
const DEFAULT_POLL_MS    = 6000;
const MIN_POLL_MS        = 3000;
const ONLINE_PRESENCE_REFRESH_MS = 240000;
const DEBOUNCE_MS        = 350;
const THREAD_PAGE_SIZE   = 20;
const MODE_FAB           = 'fab';
const MODE_UTILITY       = 'utility';
const PRIMARY_VIEW_CONVERSATIONS = 'conversations';
const PRIMARY_VIEW_BROADCAST = 'broadcast';
const RELATED_REF_NOT_FOUND_LABEL_BY_STAGE = Object.freeze({
    opportunity_negociacao: 'Cota\u00E7\u00E3o - N\u00E3o localizada',
    opportunity_analise_renda: 'AR - N\u00E3o localizada',
    opportunity_analise_credito: 'AR e AB - N\u00E3o localizadas'
});
const REPASSE_FILTER_GROUPS = {
    repasse_aguardando_inicio: {
        label: 'Aguardando início',
        values: [
            'IR FUTURO',
            'ASSINATURA DE FORMULÁRIOS',
            'AGUARDANDO PJ',
            'SFH',
            'VENDA DIRETA',
            'AGUARDANDO ENCERRAMENTO DE OBRA'
        ]
    },
    repasse_formulario: {
        label: 'Formulário',
        values: [
            'AGENDADO',
            'DÉBITO DO FGTS',
            'AGENDAR ENTREVISTA MANUAL',
            'VENDA NOVA'
        ]
    },
    repasse_conferencia_dossie: {
        label: 'Conferência de dossiê',
        values: [
            'MONTAGEM CEHOP',
            'CONFERÊNCIA'
        ]
    },
    repasse_pendencias: {
        label: 'Pendências',
        values: [
            'PENDÊNCIA PARA ENVIO',
            'INCONFORME',
            'AGUARDANDO DOCUMENTOS',
            'REAPROVAÇÃO DE CRÉDITO',
            'ANÁLISE JURÍDICA',
            'REANÁLISE JURÍDICA'
        ]
    },
    repasse_assinatura_repasse: {
        label: 'Assinatura do repasse',
        values: [
            'FECHAMENTO DE VALORES',
            'APTO PARA ASSINATURA',
            'AGENDAR ASSINATURA MANUAL',
            'ASSINATURA AGENDADA',
            'PENDENCIA CONFERENCIA EXTERNA',
            'ASSINADO PENDENCIA SANADA',
            'ASSINADO COM PENDÊNCIA',
            'ASSINADO EM CONFERÊNCIA',
            'FASE (CONFERÊNCIA) SÍNTESE (CONFERÊNCIA EXTERNA)',
            'ASSINATURA PENDÊNCIA SANADA',
            'ASSINATURA BANCO',
            'ASSINATURA DIGITAL',
            'ASSINATURA FÍSICO',
            'FASE (REGISTRO) SÍNTESE (AGUARDANDO REGISTRO)',
            'FASE (REGISTRADO) SÍNTESE (CONTRATO CONFORME)'
        ]
    },
    repasse_retencao: {
        label: 'Retenção',
        values: [
            'TROCA RETENÇÃO',
            'TROCA COMERCIAL',
            'EM NEGOCIAÇÃO',
            'FAZER CONTATO',
            'POSSÍVEL CESSÃO',
            'FASE (RETENÇÃO REPASSE) - SÍNTESE (TROCA RETENÇÃO)',
            'FASE (RETENÇÃO REPASSE) - SÍNTESE (TROCA COMERCIAL)',
            'FASE (RETENÇÃO REPASSE) - SÍNTESE (EM NEGOCIAÇÃO)',
            'FASE (RETENÇÃO REPASSE) - SÍNTESE (FAZER CONTATO)',
            'FASE (RETENÇÃO REPASSE) - SÍNTESE (POSSÍVEL CESSÃO)'
        ]
    },
    repasse_triagem: {
        label: 'Triagem',
        values: [
            'SEM CONTATO',
            'CESSÃO CONCLUÍDA',
            'RETORNO',
            'RETORNO DA RETENÇÃO',
            'RESTRIÇÃO',
            'RESTRIÇÃO SERASA/RF',
            'SEM INTERESSE',
            'SEM INTERESSE NO REPASSE',
            'NÃO ENQUADRADO',
            'NÃO LOCALIZADO',
            'FASE (RETENÇÃO REPASSE) - SÍNTESE (SEM CONTATO)',
            'FASE (TRIAGEM) - SÍNTESE (CESSÃO CONCLUÍDA)',
            'FASE (TRIAGEM) - SÍNTESE (RETORNO DA RETENÇÃO)',
            'FASE (TRIAGEM) - SÍNTESE (RESTRIÇÃO SERASA/RF)',
            'FASE (TRIAGEM) - SÍNTESE (SEM INTERESSE NO REPASSE)',
            'FASE (TRIAGEM) - SÍNTESE (NÃO ENQUADRADO)',
            'FASE (TRIAGEM) - SÍNTESE (NÃO LOCALIZADO)'
        ]
    }
};
const OPPORTUNITY_FILTER_OPTIONS = [
    { value: 'opportunity_montagem_pasta', label: 'Montagem de pasta' },
    { value: 'opportunity_analise_renda', label: 'Análise de renda (AR)' },
    { value: 'opportunity_analise_credito', label: 'Análise de crédito' },
    { value: 'opportunity_negociacao', label: 'Negociação' },
    { value: 'opportunity_condicao_credito', label: 'Condição crédito' },
    { value: 'opportunity_condicao_comercial', label: 'Condição comercial' },
    { value: 'opportunity_contrato', label: 'Contrato' },
    { value: 'opportunity_ganha', label: 'Oportunidade ganha' }
];
const REPASSE_FILTER_OPTIONS = [
    { value: 'repasse_aguardando_inicio', label: 'Aguardando início' },
    { value: 'repasse_formulario', label: 'Formulário' },
    { value: 'repasse_conferencia_dossie', label: 'Conferência de dossiê' },
    { value: 'repasse_pendencias', label: 'Pendências' },
    { value: 'repasse_assinatura_repasse', label: 'Assinatura do repasse' },
    { value: 'repasse_retencao', label: 'Retenção' },
    { value: 'repasse_triagem', label: 'Triagem' },
    { value: 'repasse_outros', label: 'Outros' }
];
const REPASSE_MACRO_PHASES = new Set([
    'aguardando inicio',
    'formulario',
    'conferencia de dossie',
    'pendencias',
    'assinatura do repasse',
    'retencao',
    'triagem',
    'outros'
]);
const REPASSE_FILTER_VALUE_BY_MACRO_PHASE = Object.freeze({
    'aguardando inicio': 'repasse_aguardando_inicio',
    formulario: 'repasse_formulario',
    'conferencia de dossie': 'repasse_conferencia_dossie',
    pendencias: 'repasse_pendencias',
    'assinatura do repasse': 'repasse_assinatura_repasse',
    retencao: 'repasse_retencao',
    triagem: 'repasse_triagem',
    outros: 'repasse_outros'
});
const STATUS_STYLE_MAP = {
    'ir futuro': 'comm-picker__badge comm-picker__badge--violet',
    'aguardando pj': 'comm-picker__badge comm-picker__badge--sky',
    'sfh': 'comm-picker__badge comm-picker__badge--lime',
    'venda direta': 'comm-picker__badge comm-picker__badge--pink',
    '1 cotação': 'comm-picker__badge comm-picker__badge--indigo-soft',
    '1 cotacao': 'comm-picker__badge comm-picker__badge--indigo-soft',
    'emitido': 'comm-picker__badge comm-picker__badge--indigo',
    'em emissão': 'comm-picker__badge comm-picker__badge--cyan-soft',
    'em emissao': 'comm-picker__badge comm-picker__badge--cyan-soft',
    'em montagem': 'comm-picker__badge comm-picker__badge--yellow-soft',
    'com pendência': 'comm-picker__badge comm-picker__badge--lavender',
    'com pendencia': 'comm-picker__badge comm-picker__badge--lavender',
    'aguardando documento': 'comm-picker__badge comm-picker__badge--sand',
    'pendência sistêmica': 'comm-picker__badge comm-picker__badge--cyan',
    'pendencia sistemica': 'comm-picker__badge comm-picker__badge--cyan',
    'análise jurídica': 'comm-picker__badge comm-picker__badge--blue-soft',
    'analise juridica': 'comm-picker__badge comm-picker__badge--blue-soft',
    'sem agendamento': 'comm-picker__badge comm-picker__badge--rose',
    'agendado': 'comm-picker__badge comm-picker__badge--teal',
    'assinado pelo banco': 'comm-picker__badge comm-picker__badge--purple-soft',
    'aguardando registro': 'comm-picker__badge comm-picker__badge--amber-soft',
    'registrado': 'comm-picker__badge comm-picker__badge--ice',
    'tag retenção': 'comm-picker__badge comm-picker__badge--stone',
    'tag retencao': 'comm-picker__badge comm-picker__badge--stone',
    'tag triagem': 'comm-picker__badge comm-picker__badge--beige',
    'análise de crédito': 'comm-picker__badge comm-picker__badge--pink',
    'analise de credito': 'comm-picker__badge comm-picker__badge--pink',
    'montagem de pasta': 'comm-picker__badge comm-picker__badge--yellow-soft',
    'apuração de renda': 'comm-picker__badge comm-picker__badge--orange-soft',
    'apuracao de renda': 'comm-picker__badge comm-picker__badge--orange-soft',
    '3 cotações': 'comm-picker__badge comm-picker__badge--indigo-soft',
    '3 cotacoes': 'comm-picker__badge comm-picker__badge--indigo-soft',
    'aprovação da condição crédito': 'comm-picker__badge comm-picker__badge--mint',
    'aprovacao da condicao credito': 'comm-picker__badge comm-picker__badge--mint',
    'condição comercial': 'comm-picker__badge comm-picker__badge--aqua-soft',
    'condicao comercial': 'comm-picker__badge comm-picker__badge--aqua-soft',
    'aguardando contrato': 'comm-picker__badge comm-picker__badge--lavender',
    'preparação do contrato': 'comm-picker__badge comm-picker__badge--gold-soft',
    'preparacao do contrato': 'comm-picker__badge comm-picker__badge--gold-soft',
    'contrato enviado': 'comm-picker__badge comm-picker__badge--blue-strong',
    'contrato assinado cliente': 'comm-picker__badge comm-picker__badge--indigo-strong',
    'desembolsado': 'comm-picker__badge comm-picker__badge--green-soft'
};

export default class CommunicatorChatFloatingButton extends NavigationMixin(LightningElement) {

    @api mode = MODE_FAB;
    // Ativado apenas pelo wrapper do Salesforce mobile app. Mantem o layout
    // desktop/community intacto.
    @api mobileMode = false;
    @wire(EnclosingUtilityId) enclosingUtilityId;

    // ─── Estado FAB / Chat (inalterado) ─────────────────────────────
    @track isOpen             = false;
    @track showChat           = false;
    @track activePrimaryView  = PRIMARY_VIEW_CONVERSATIONS;
    @track threadId           = null;
    @track opportunityId      = null;
    @track opportunityName    = '';
    @track opportunityStage   = '';
    @track opportunityStageClass = 'comm-picker__badge comm-picker__badge--default';
    @track opportunityStatusLabel = 'Fase atual:';
    @track activeRecordTypeLabel = 'Oportunidade';
    @track activeRecordTypeClass = 'comm-picker__badge comm-picker__badge--orange';
    @track opportunityArId    = null;
    @track opportunityArName  = '';
    @track opportunityRelatedRefType = null;
    @track opportunityRelatedRefObjectApiName = null;
    @track showChatterHistory = false;
    @track chatterSearchTerm  = '';
    @track chatterSearchResults = [];
    @track isChatterSearchLoading = false;
    @track isChatterSearchComplete = false;
    @track isLoadingThread    = false;
    @track loadError          = null;
    @track showSearch         = false;
    @track broadcastImagePreview = null;
    @track isBroadcastTimelineOpen = false;
    @track highlightMessageId = null;
    @track unreadCount        = 0;
    @track globalUnreadCount  = 0;
    @track broadcastUnreadTotal = 0;
    @track recentOpportunities = [];
    @track recentStageByOpportunityId = {};
    @track relatedRefsByOpportunityId = {};
    @track historyMessages  = [];
    @track isLoadingHistory = false;
    @track chatThreadIds    = [];

    // ─── Estado da lista de threads (novo) ──────────────────────────
    @track threads           = [];
    @track _rawThreads       = [];
    @track totalCount        = 0;
    @track isLoadingList     = false;
    @track activeFilter      = 'all';
    @track _unreadTabCount   = 0;
    @track keyword           = '';
    @track showStageDropdown = false;
    @track _groups           = [];
    @track _isLoadingGroups  = false;
    @track _inGroupView           = false;
    @track _activeGroup           = null;
    @track _activeGroupThreadId   = null;
    @track _groupHighlightMsgId   = null;
    @track _etapaFilter      = '';
    @track _stageFilters     = [];

    @track socketStatus = 'offline'; // 'online' | 'offline' | 'connecting'
    @track threadPresenceStatusByUserId = {};
    @track threadPresenceOverrideByThreadId = {};
    @track liveNotificationCount = 0;
    @track liveNotificationTargetRecordId = null;
    @track liveNotificationTargetRecordName = '';
    @track liveNotificationTargetObjectType = 'Opportunity';
    @track liveNotificationTargetThreadId = null;
    _socketUnsubscribes = [];
    _socketAcquired = false;
    _liveNotificationSequence = 0;
    _liveSnapshotPromise = null;

    _isSalesforcePlatformUser = false;
    _chatCurrentStage = '';

    @track _hasPermission       = true;
    @track _noPermissionMessage = '';

    _pollTimer        = null;
    _globalUnreadPollTimer = null;
    _listPollTimer    = null;
    _presenceOnlinePollTimer = null;
    _pollIntervalMs   = DEFAULT_POLL_MS;
    _searchDebounce   = null;
    _hasGroupAccess   = false;
    _isConnected      = false;
    _broadcastUnreadRequestVersion = 0;
    _broadcastUnreadInFlight = false;
    _broadcastUnreadRefreshQueued = false;
    _broadcastImagePreviewReturnFocus = null;
    _isBroadcastImagePreviewModalPending = false;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    async connectedCallback() {
        this._isConnected = true;
        this._refreshRecents().catch(() => {});
        await this._loadConfig();
        if (!this._hasPermission) return;
        this._loadThreadList();
        this._loadGroups();
        this._refreshGlobalUnreadCount().catch(() => {});
        this._refreshBroadcastUnreadTotal();
        this._startGlobalUnreadPolling();
        this._startListPolling();
        this.initSocket();
    }

    disconnectedCallback() {
        this._isConnected = false;
        this.teardownSocket();
        this._stopPolling();
        this._stopGlobalUnreadPolling();
        this._stopListPolling();
        this._stopPresenceOnlinePolling();
        this._invalidateBroadcastUnreadRequests();
        this._clearBroadcastImagePreview();
        this._resetCompactChatterHistory();
    }

    // ─────────────────────────────────────────
    // FAB toggle (inalterado)
    // ─────────────────────────────────────────

    handleToggle() {
        if (this.isUtilityMode) return;
        if (this.isOpen) {
            this._closeBroadcastImagePreview({ notifyWorkspace: true });
            this._resetCompactChatterHistory();
        }
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            this._queueThreadPresenceRefresh();
        } else {
            this._stopPresenceOnlinePolling();
        }
    }

    handleClose() {
        if (this.isUtilityMode) return;
        this._closeBroadcastImagePreview({ notifyWorkspace: true });
        this._resetCompactChatterHistory();
        this.isOpen = false;
        this._stopPresenceOnlinePolling();
    }

    get isHistoryActionDisabled() {
        return isSalesforceMobileApp(this.mobileMode);
    }

    get historyButtonTitle() {
        return this.isHistoryActionDisabled ? SALESFORCE_APP_DISABLED_MESSAGE : null;
    }

    get historyButtonAriaDisabled() {
        return this.isHistoryActionDisabled ? 'true' : null;
    }

    get expandButtonClass() {
        return this.isHistoryActionDisabled ? 'comm-picker__expand-btn comm-is-disabled' : 'comm-picker__expand-btn';
    }

    get historyButtonClass() {
        return this.isHistoryActionDisabled ? 'comm-chat__history-btn comm-is-disabled' : 'comm-chat__history-btn';
    }

    _blockHistoryInSalesforceApp() {
        if (!this.isHistoryActionDisabled) return false;
        this.dispatchEvent(buildDisabledFeatureToast());
        return true;
    }

    handleOpenHistory() {
        if (this._blockHistoryInSalesforceApp()) return;
        this._closeBroadcastImagePreview({ notifyWorkspace: true });
        if (!this.isFabMode) {
            // Internal (chore): abrir histórico completo sem selecionar uma conversa específica
            this._minimizeCompactWindow();
            this._openHistoryModal({ size: 'large' })
                .then(result => this._handleModalResult(result))
                .catch(error => console.error('CommunicatorChatFloatingButton.handleOpenHistory:', error));
            return;
        }
        this._minimizeCompactWindow();
        this._navigateToHistory(this.opportunityId);
    }

    handlePrimaryViewSelect(event) {
        const nextView = event.currentTarget?.dataset?.view;
        if (!nextView || nextView === this.activePrimaryView || this.showChat) return;
        if (this.activePrimaryView === PRIMARY_VIEW_BROADCAST && nextView !== PRIMARY_VIEW_BROADCAST) {
            this._closeBroadcastImagePreview({ notifyWorkspace: true });
        }
        this.isBroadcastTimelineOpen = false;
        this.activePrimaryView = nextView;
        this.loadError = null;
        this.showStageDropdown = false;
        this._refreshBroadcastUnreadTotal();
    }

    handleBroadcastViewChange(event) {
        this.isBroadcastTimelineOpen = event.detail?.isTimelineView === true;
    }

    // ─────────────────────────────────────────
    // Abas / Busca / Filtros da lista (novo)
    // ─────────────────────────────────────────

    handleFilterSelect(event) {
        const nextView = event.currentTarget?.dataset?.view;
        if (nextView === PRIMARY_VIEW_BROADCAST) {
            if (this.activePrimaryView === PRIMARY_VIEW_BROADCAST) return;
            this._resetConversationSelectionState();
            this.activePrimaryView = PRIMARY_VIEW_BROADCAST;
            this.loadError = null;
            this.showStageDropdown = false;
            this._refreshBroadcastUnreadTotal();
            return;
        }

        const wasBroadcast = this.activePrimaryView === PRIMARY_VIEW_BROADCAST;
        if (wasBroadcast) {
            this._closeBroadcastImagePreview({ notifyWorkspace: true });
            this.activePrimaryView = PRIMARY_VIEW_CONVERSATIONS;
        }

        const filter = event.currentTarget.dataset.filter;
        if (filter === this.activeFilter && !wasBroadcast) return;
        this.activeFilter  = filter;
        this._resetConversationSelectionState();
        if (filter === 'groups') {
            this._loadGroups();
        } else {
            this._loadThreadList();
        }
    }

    handleBroadcastUnreadChange() {
        this._refreshBroadcastUnreadTotal();
    }

    async handleBroadcastImagePreviewOpen(event) {
        const src = String(event?.detail?.src || '').trim();
        if (!src) return;

        const fileName = String(event?.detail?.fileName || '').trim() || 'Imagem anexada';
        const alternativeText = String(event?.detail?.alternativeText || '').trim() || `Imagem anexada: ${fileName}`;
        if (this.isUtilityMode) {
            if (this._isBroadcastImagePreviewModalPending) return;
            this._broadcastImagePreviewReturnFocus = this._resolveBroadcastImagePreviewFocusTarget();
            await this._openBroadcastImagePreviewModal({
                src,
                fileName,
                alternativeText
            });
            return;
        }

        this._broadcastImagePreviewReturnFocus = this._resolveBroadcastImagePreviewFocusTarget();
        this.broadcastImagePreview = {
            src,
            fileName,
            alternativeText
        };
    }

    handleBroadcastImagePreviewClose() {
        this._closeBroadcastImagePreview({ notifyWorkspace: true, restoreFocus: true });
    }

    handleBroadcastImagePreviewReset() {
        if (this.isUtilityMode) return;
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
        return 'comm-picker__tab-badge comm-picker__tab-badge--broadcast';
    }

    handleGroupSelect(event) {
        const groupId = event.currentTarget.dataset.groupId;
        this._activeGroup         = this._groups.find(g => g.groupId === groupId) || null;
        this._inGroupView         = true;
        this._activeGroupThreadId = null;
        this._groupHighlightMsgId = null;
        this._groups = this._groups.map(g =>
            g.groupId === groupId ? { ...g, unreadMentionCount: 0 } : g
        );
        markGroupMentionsAsRead({ groupId }).catch(console.error);
    }

    handleGroupBack() {
        this._inGroupView         = false;
        this._activeGroup         = null;
        this._activeGroupThreadId = null;
        this._groupHighlightMsgId = null;
    }

    _resetConversationSelectionState() {
        this.keyword              = '';
        this._etapaFilter         = '';
        this._stageFilters        = [];
        this._rawThreads          = [];
        this.threads              = [];
        this._inGroupView         = false;
        this._activeGroup         = null;
        this._activeGroupThreadId = null;
        this._groupHighlightMsgId = null;
        this._closeBroadcastImagePreview({ notifyWorkspace: true });
        this._resetCompactChatterHistory();
    }

    handleGroupThreadReady(event) {
        this._activeGroupThreadId = event.detail.threadId;
    }

    handleGroupNavigateMessage(event) {
        this._groupHighlightMsgId = event.detail.messageId;
    }

    async _loadGroups(silent = false) {
        if (!silent) this._isLoadingGroups = true;
        try {
            this._groups = await getGroupsWithStats() || [];
        } catch (e) {
            console.error('[communicatorChatFloatingButton] _loadGroups:', e);
            this._groups = [];
        } finally {
            if (!silent) this._isLoadingGroups = false;
            this._refreshBroadcastUnreadTotal();
        }
    }

    handleSearchInput(event) {
        this.keyword = event.target.value;
        clearTimeout(this._searchDebounce);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchDebounce = setTimeout(() => this._loadThreadList(), DEBOUNCE_MS);
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
        this._applyFilter();
    }

    handleStageChange(event) {
        const val = event.target.value;
        if (event.target.checked) {
            this._stageFilters = [...this._stageFilters, val];
        } else {
            this._stageFilters = this._stageFilters.filter(v => v !== val);
        }
        this._applyFilter();
    }

    handleClearFilters() {
        this._etapaFilter      = '';
        this._stageFilters     = [];
        this.showStageDropdown = false;
        this._applyFilter();
    }

    // ─────────────────────────────────────────
    // Opportunity selection (inalterado)
    // ─────────────────────────────────────────

    handleOpportunitySelect(event) {
        const recordId = event.detail.recordId;
        if (!recordId) return;
        const name = event.detail?.record?.fields?.Name?.value || 'Opportunity';
        this._openChat(recordId, name, 'Opportunity');
    }

    handleRecentClick(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        const objectType = event.currentTarget.dataset.objecttype || 'Opportunity';
        const threadId = event.currentTarget.dataset.threadid || null;
        const selectedThreadCard = this._resolveSelectedThreadCard(id, objectType, threadId);
        this._openChat(id, name, objectType, selectedThreadCard);
    }

    handleBack() {
        this._stopPolling();
        this._closeBroadcastImagePreview({ notifyWorkspace: true });
        this._resetCompactChatterHistory();
        this.showChat           = false;
        this.threadId           = null;
        this.opportunityId      = null;
        this.showSearch         = false;
        this.highlightMessageId = null;
        this.unreadCount        = 0;
        this.loadError          = null;
        this.opportunityName    = '';
        this.opportunityStage   = '';
        this.opportunityStageClass = 'comm-picker__badge comm-picker__badge--default';
        this.opportunityStatusLabel = 'Fase atual:';
        this.activeRecordTypeLabel = 'Oportunidade';
        this.activeRecordTypeClass = 'comm-picker__badge comm-picker__badge--orange';
        this.opportunityArId    = null;
        this.opportunityArName  = '';
        this.opportunityRelatedRefType = null;
        this.opportunityRelatedRefObjectApiName = null;
        this.chatThreadIds      = [];
        this._chatCurrentStage  = '';
        this._loadThreadList();
        this._startListPolling();
    }

    async handleOpenOpportunity() {
        await this._navigateToOpportunity();
    }

    handleOpenConversationHistory() {
        if (this._blockHistoryInSalesforceApp()) return;
        this._logCurrentChatDebugUrls();
        if (!this.isFabMode) {
            // Internal (chore): abrir histórico já posicionado na conversa da oportunidade atual
            this._minimizeCompactWindow();
            this._openHistoryModal({ size: 'large', recordId: this.opportunityId })
                .then(result => this._handleModalResult(result))
                .catch(error => console.error('CommunicatorChatFloatingButton.handleOpenConversationHistory:', error));
            return;
        }
        this._minimizeCompactWindow();
        this._navigateToHistory(this.opportunityId);
    }

    handleToggleChatterHistory() {
        if (!this.canShowCompactChatterToggle) {
            this._resetCompactChatterHistory();
            return;
        }

        this.showChatterHistory = !this.showChatterHistory;
        this._resetCompactChatterSearchState();
        this.highlightMessageId = null;
    }

    handleCompactChatterSearchChange(event) {
        this.chatterSearchTerm = event.detail?.keyword || '';
    }

    handleCompactChatterSearchStateChange(event) {
        this.chatterSearchResults = Array.isArray(event.detail?.results) ? event.detail.results : [];
        this.isChatterSearchLoading = event.detail?.isSearching === true;
        this.isChatterSearchComplete = event.detail?.isComplete === true;
    }

    async handleCompactChatterNavigateToMessage(event) {
        const feedItemId = event.detail?.messageId;
        if (!feedItemId) return;

        const match = (this.chatterSearchResults || []).find((result) => result.Id === feedItemId);
        this.showSearch = false;
        this._resetCompactChatterSearchState();
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

    _logCurrentChatDebugUrls() {
        const internalOrigin = this._resolveInternalSalesforceOrigin();
        const normalizedOpportunityId = String(this.opportunityId || '').trim();
        const currentThreadId = this.threadId || (this.chatThreadIds && this.chatThreadIds.length > 0 ? this.chatThreadIds[0] : null);
        if (normalizedOpportunityId.startsWith('006')) {
            const opportunityRecordUrl = `${internalOrigin}/lightning/r/Opportunity/${normalizedOpportunityId}/view`;
            console.log(`[Comunicador Compacto] URL da oportunidade: ${opportunityRecordUrl}`);
        }
        if (currentThreadId) {
            const threadRecordUrl = `${internalOrigin}/lightning/r/CommunicatorThread__c/${currentThreadId}/view`;
            console.log(`[Comunicador Compacto] URL da thread: ${threadRecordUrl}`);
        }
    }

    handleArClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const relatedRecordId = event.currentTarget?.dataset?.relatedId || event.currentTarget?.dataset?.arId;
        const relatedRecordName = event.currentTarget?.dataset?.relatedName || event.currentTarget?.dataset?.arName;
        const relatedRecordType = event.currentTarget?.dataset?.relatedType || 'ar';
        const normalizedRelatedRecordType = String(relatedRecordType || '').toLowerCase();
        const relatedObjectApiName = event.currentTarget?.dataset?.relatedObjectApiName || this._objectApiNameByRelatedRefType(normalizedRelatedRecordType);
        if (!relatedRecordId) return;

        if (this._isBrokerCommunityContext()
            && this._openBrokerCommunityRelatedRecord(normalizedRelatedRecordType, relatedRecordId, relatedRecordName)) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: relatedRecordId,
                objectApiName: relatedObjectApiName,
                actionName: 'view'
            }
        });
    }

    _openBrokerCommunityRelatedRecord(relatedRecordType, relatedRecordId, relatedRecordName) {
        if (relatedRecordType === 'ar' || relatedRecordType === 'analise_credito') {
            this._openBrokerCommunityAnaliseFinanceira(relatedRecordId, relatedRecordName);
            return true;
        }
        if (relatedRecordType === 'ab') {
            this._openBrokerCommunityDetail(relatedRecordId);
            return true;
        }
        if (relatedRecordType === 'quote') {
            this._openBrokerCommunityQuote(relatedRecordId, relatedRecordName);
            return true;
        }
        return false;
    }

    _objectApiNameByRelatedRefType(relatedRefType) {
        if (relatedRefType === 'ab') return 'AprovacaoBancaria__c';
        if (relatedRefType === 'quote') return 'Quote';
        return 'AnaliseFinanceira__c';
    }

    _openBrokerCommunityAnaliseFinanceira(arId, arName) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        const arSlug = this._normalizeAnaliseFinanceiraSlug(arName);
        const arSlugSegment = arSlug ? `/${arSlug}` : '';
        const brokerCommunityAnaliseFinanceiraUrl = `${normalizedBasePath}/corretores/s/analisefinanceira/${arId}${arSlugSegment}`;

        window.open(brokerCommunityAnaliseFinanceiraUrl, '_blank');
    }

    _openBrokerCommunityQuote(quoteId, quoteName) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        const quoteSlug = this._normalizeCommunityQuoteSlug(quoteName);
        const quoteSlugSegment = quoteSlug ? `/${encodeURIComponent(quoteSlug)}` : '';
        const brokerCommunityQuoteUrl = `${normalizedBasePath}/corretores/s/quote/${quoteId}${quoteSlugSegment}`;

        window.open(brokerCommunityQuoteUrl, '_blank');
    }

    _openBrokerCommunityDetail(recordId) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        const brokerCommunityDetailUrl = `${normalizedBasePath}/corretores/s/detail/${recordId}`;
        window.open(brokerCommunityDetailUrl, '_blank');
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

    // ─────────────────────────────────────────
    // Thread loading (inalterado)
    // ─────────────────────────────────────────

    handlePickerSelected(event) {
        const { recordId, name, objectType } = event.detail || {};
        if (!recordId) return;
        this._openChat(recordId, name || '', objectType || '');
    }

    async _openChat(recordId, name, objectType, selectedThreadCard = null, forcedThreadId = null) {
        this._stopListPolling();
        this._resetCompactChatterHistory();
        this.isLoadingThread  = true;
        this.loadError        = null;
        this.opportunityName  = name;
        this.opportunityId    = recordId;

        try {
            // For Repasse__c object cards the DTO carries a Repasse__c ID as recordId.
            // We must resolve the linked Opportunity ID so Apex routes to the correct
            // repasse thread (RecordType__c='Opportunity' + Stage = repasse macro phase).
            // Passing objectType='Repasse__c' makes Apex create a separate thread with
            // RecordType__c='Repasse__c', which differs from the thread ensureRepasseThread
            // creates, causing messages to not appear in the history component.
            let threadRecordId = recordId;
            if (objectType === 'Repasse__c') {
                const allCards = [...(this._rawThreads || []), ...(this.threads || [])];
                const repasseCard = allCards.find(c => c?.recordId === recordId && c?.recordType === 'Repasse__c');
                if (repasseCard?.repasseOpportunityId) {
                    threadRecordId = repasseCard.repasseOpportunityId;
                }
            }
            const thread  = await getOrCreateThread({ recordId: threadRecordId, objectType: 'Opportunity' });
            this.threadId = thread.Id;
            this._chatCurrentStage = thread?.Stage__c || '';
            this.showChat = true;
            this._queueThreadPresenceRefresh();

            // Resolve the final opportunity ID (thread.RecordId__c is always the Opportunity)
            const resolvedRecordId = thread?.RecordId__c || threadRecordId;
            if (resolvedRecordId && resolvedRecordId !== recordId) {
                this.opportunityId = resolvedRecordId;
                if (!this._isSalesforcePlatformUser || objectType !== 'Repasse__c') {
                    try {
                        this.opportunityName = await getRecordName({ recordId: resolvedRecordId });
                    } catch (e) { /* silent */ }
                }
            }
            const recordThreads = await getThreadsForRecord({ recordId: this.opportunityId });
            const allThreadIds = [...new Set(
                (recordThreads || [])
                    .map(t => t?.threadId)
                    .filter(Boolean)
            )];
            if (thread?.Id && !allThreadIds.includes(thread.Id)) {
                allThreadIds.push(thread.Id);
            }
            this.chatThreadIds = allThreadIds;

            const selected = selectedThreadCard
                || this._resolveSelectedThreadCard(this.opportunityId, objectType, thread?.Id);

            // Derive currentRecordType with selected card priority, then fallback to
            // thread stage. This keeps compact behavior aligned with the selected card.
            const threadStage = thread?.Stage__c || '';
            const currentRecordType = this._effectiveRecordType(
                selected?.recordType || objectType || 'Opportunity',
                selected?.hasRepasse || this._isRepasseMacroPhase(threadStage)
            );

            if (forcedThreadId && !allThreadIds.includes(forcedThreadId)) {
                allThreadIds.push(forcedThreadId);
            }
            // In Repasse mode thread.Id is already authoritative (resolved server-side
            // via ensureThreadForRepassePhase). Never let a card's cached threadId
            // override it — the card may point to a different phase.
            const selectedThreadId = currentRecordType !== 'Repasse__c'
                ? (selected?.threadId || null)
                : null;
            const preferredThreadId = forcedThreadId || selectedThreadId || null;
            if (preferredThreadId && !allThreadIds.includes(preferredThreadId)) {
                allThreadIds.push(preferredThreadId);
            }
            this.threadId = preferredThreadId || thread.Id;
            // Capture final threadId before further awaits — handleBack may reset this.threadId.
            const _finalThreadId = this.threadId;
            this.chatThreadIds = allThreadIds;
            this._clearLiveNotificationIfMatchingOpenChat(this.threadId, this.opportunityId);
            this._logCurrentChatDebugUrls();

            this.activeRecordTypeLabel = this._recordTypeLabel(currentRecordType);
            this.activeRecordTypeClass = this._recordTypeClass(currentRecordType);

            await this._hydrateOpportunityRelatedRefs([this.opportunityId]);
            const relatedRefs = this.relatedRefsByOpportunityId?.[this.opportunityId];
            const recordInfo = selected || {
                currentStage: thread?.Stage__c || '',
                stageName: thread?.Stage__c || '',
                recordType: currentRecordType,
                hasRepasse: currentRecordType === 'Repasse__c'
            };
            const displayStatus = this._buildDisplayStatusData(recordInfo, relatedRefs);
            this.opportunityStage      = displayStatus.value;
            this.opportunityStageClass = displayStatus.className;
            this.opportunityStatusLabel = displayStatus.label;
            const activeRelatedRef = this._buildCompactRelatedRef(recordInfo, relatedRefs);
            this.opportunityArId   = activeRelatedRef?.id || null;
            this.opportunityArName = activeRelatedRef?.name || '';
            this.opportunityRelatedRefType = activeRelatedRef?.type || null;
            this.opportunityRelatedRefObjectApiName = activeRelatedRef?.objectApiName || null;
            this._validatePresenceIdsOnChatOpen().catch(() => {});
            markThreadAsRecentlyViewed({ threadId: _finalThreadId }).catch(() => {});
            this._refreshRecents().catch(() => {});
            this._startPolling();
            const markReadPromises = this.chatThreadIds.length > 0
                ? this.chatThreadIds.map(threadId => markThreadAsRead({ threadId }))
                : [markThreadAsRead({ threadId: this.threadId })];
            await Promise.all(markReadPromises);
            this.unreadCount = 0;
            await this._refreshGlobalUnreadCount();
        } catch (err) {
            this.loadError = err.body?.message || err.message || 'Failed to open chat.';
            console.error('CommunicatorChatFloatingButton._openChat:', err);
            this._startListPolling();
        } finally {
            this.isLoadingThread = false;
        }
    }

    _logInternalOpportunityDebugUrl(opportunityId) {
        const normalizedOpportunityId = String(opportunityId || '').trim();
        if (!normalizedOpportunityId.startsWith('006')) return;

        const internalOrigin = this._resolveInternalSalesforceOrigin();
        const internalOpportunityUrl = `${internalOrigin}/lightning/r/Opportunity/${normalizedOpportunityId}/view`;

        console.log(`[Communicator Debug] Opportunity URL interna: ${internalOpportunityUrl}`);
    }

    _resolveInternalSalesforceOrigin() {
        const currentProtocol = window.location?.protocol || 'https:';
        const currentHostName = window.location?.hostname || '';

        if (currentHostName.includes('.my.site.com')) {
            const internalHostName = currentHostName.replace('.my.site.com', '.lightning.force.com');
            return `${currentProtocol}//${internalHostName}`;
        }

        return window.location?.origin || '';
    }

    async _navigateToOpportunity(targetOpportunityId = this.opportunityId) {
        if (!targetOpportunityId) return;

        try {
            if (this._isBrokerCommunityContext()) {
                this._openBrokerCommunityOpportunity(targetOpportunityId);
                await this._minimizeCompactWindow();
                return;
            }
            if (this._isSalesforcePlatformUser) {
                const repasseId = await getRepasseIdByOppId({ opportunityId: targetOpportunityId });
                if (repasseId) {
                    this._navigateToRecord(repasseId, 'Repasse__c');
                    await this._minimizeCompactWindow();
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Aviso',
                        message: 'Repasse não encontrado para a oportunidade',
                        variant: 'warning'
                    }));
                }
                return;
            }
            const redirect = await resolveOpportunityAccessRedirect({ opportunityId: targetOpportunityId });
            const shouldForceCommunityDetailUrl = redirect?.forceCommunityDetailUrl === true || redirect?.forceCommunityDetailUrl === 'true';
            if (shouldForceCommunityDetailUrl) {
                this._openBrokerCommunityOpportunity(targetOpportunityId);
                await this._minimizeCompactWindow();
                return;
            }
            if (redirect?.action === 'navigateToRecord' && redirect?.recordId) {
                this._navigateToRecord(redirect.recordId, this._resolveObjectApiNameForNavigation(redirect.objectApiName));
                await this._minimizeCompactWindow();
                return;
            }
            this._showNoAccessMessage(redirect?.message);
        } catch (error) {
            this._showNoAccessMessage();
            console.error('CommunicatorChatFloatingButton._navigateToOpportunity:', error);
        }
    }

    async handleLiveNotificationClick() {
        if (!this.liveNotificationTargetRecordId) {
            this._clearLiveNotificationBadge();
            return;
        }
        const targetRecordId = this.liveNotificationTargetRecordId;
        const targetObjectType = this.liveNotificationTargetObjectType || 'Opportunity';
        const targetThreadId = this.liveNotificationTargetThreadId || null;
        const targetRecordName = this.liveNotificationTargetRecordName || 'Oportunidade';
        const selectedThreadCard = this._resolveSelectedThreadCard(
            targetRecordId,
            targetObjectType,
            targetThreadId
        );
        this._clearLiveNotificationBadge();
        await this._openChat(
            targetRecordId,
            targetRecordName,
            targetObjectType,
            selectedThreadCard,
            targetThreadId
        );
    }

    _minimizeCompactWindow() {
        if (this.isFabMode) {
            this.isOpen = false;
            return;
        }
        if (!this.isUtilityMode || !this.enclosingUtilityId) return;
        return minimize(this.enclosingUtilityId).catch(error => {
            console.error('CommunicatorChatFloatingButton._minimizeCompactWindow:', error);
        });
    }

    _navigateToRecord(recordId, objectApiName) {
        if (!recordId) return;
        if (this._isOpportunityNavigationTarget(recordId, objectApiName) && this._isBrokerCommunityContext()) {
            this._openBrokerCommunityOpportunity(recordId);
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    _isOpportunityNavigationTarget(recordId, objectApiName) {
        const normalizedObjectApiName = String(objectApiName || '').trim().toLowerCase();
        const normalizedRecordId = String(recordId || '').trim();
        return normalizedObjectApiName === 'opportunity' || normalizedRecordId.startsWith('006');
    }

    _resolveObjectApiNameForNavigation(objectApiName) {
        return objectApiName || 'Opportunity';
    }

    _showNoAccessMessage(message) {
        const warningMessage = message || 'Você não tem permissão para ver o registro.';
        this.dispatchEvent(new ShowToastEvent({
            title: 'Acesso negado',
            message: warningMessage,
            variant: 'warning'
        }));
    }

    _isBrokerCommunityContext() {
        const currentPathname = (window.location?.pathname || '').toLowerCase();
        const currentHostname = (window.location?.hostname || '').toLowerCase();
        const isBrokerCommunityHost = currentHostname.includes('.my.site.com');
        const isBrokerCommunityPath = currentPathname.includes('/corretores')
            || currentPathname.includes('/s/')
            || currentPathname.includes('/kanban');

        return isBrokerCommunityHost || isBrokerCommunityPath;
    }

    _openBrokerCommunityOpportunity(opportunityId) {
        const normalizedBasePath = this._normalizeBrokerCommunityBasePath();
        const brokerCommunityOpportunityUrl = `${normalizedBasePath}/corretores/s/opportunity/${opportunityId}`;
        window.open(brokerCommunityOpportunityUrl, '_blank');
    }

    _normalizeBrokerCommunityBasePath() {
        const currentPathname = String(window.location?.pathname || '');
        const pathnameWithoutRoute = currentPathname.includes('/s/')
            ? currentPathname.split('/s/')[0]
            : currentPathname;

        const normalizedBasePath = pathnameWithoutRoute
            .replace(/\/kanban.*$/i, '')
            .replace(/\/+$/, '');
        return normalizedBasePath.replace(/\/corretores$/i, '');
    }

    async _handleModalResult(result) {
        if (!result) return;
        if (result.action === 'navigateToRecord') {
            const targetObjectApiName = result.objectType || 'Opportunity';
            if (this._isOpportunityNavigationTarget(result.recordId, targetObjectApiName)) {
                await this._navigateToOpportunity(result.recordId);
                return;
            }
            this._navigateToRecord(result.recordId, targetObjectApiName);
        } else if (result.action === 'navigateToAr') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId:   result.arId,
                    actionName: 'view'
                }
            });
        }
    }

    _openHistoryModal(options) {
        const opener = this.template.querySelector('c-communicator-chat-history-modal-opener');
        if (opener) {
            return opener.open(options);
        }

        let handled = false;
        return new Promise((resolve, reject) => {
            this.dispatchEvent(new CustomEvent('requesthistorymodal', {
                detail: {
                    options,
                    resolve,
                    reject,
                    markHandled: () => {
                        handled = true;
                    }
                }
            }));

            Promise.resolve().then(() => {
                if (!handled) {
                    reject(new Error('Communicator history modal opener is not available.'));
                }
            });
        });
    }

    _openBroadcastImagePreviewModal(options) {
        this._isBroadcastImagePreviewModalPending = true;

        return this._requestBroadcastImagePreviewModal(options)
            .catch(error => {
                console.error('CommunicatorChatFloatingButton._openBroadcastImagePreviewModal:', error);
            })
            .finally(() => {
                this._isBroadcastImagePreviewModalPending = false;
                this._finalizeUtilityBroadcastImagePreview();
            });
    }

    _requestBroadcastImagePreviewModal(options) {
        let handled = false;
        return new Promise((resolve, reject) => {
            this.dispatchEvent(new CustomEvent('requestbroadcastimagepreviewmodal', {
                detail: {
                    options,
                    resolve,
                    reject,
                    markHandled: () => {
                        handled = true;
                    }
                }
            }));

            Promise.resolve().then(() => {
                if (!handled) {
                    reject(new Error('Communicator broadcast image preview modal opener is not available.'));
                }
            });
        });
    }

    _navigateToHistory(opportunityId) {
        const pageRef = {
            type: 'comm__namedPage',
            attributes: { name: 'comunicatorHistory__c' }
        };
        if (opportunityId) {
            pageRef.state = { c__opportunityId: opportunityId };
        }
        this[NavigationMixin.Navigate](pageRef);
    }

    // ─────────────────────────────────────────
    // Chat handlers (inalterados)
    // ─────────────────────────────────────────

    handleToggleSearch() {
        this.showSearch = !this.showSearch;
        if (!this.showSearch) {
            this.highlightMessageId = null;
            if (this.showCompactChatterSection) {
                this._resetCompactChatterSearchState();
            }
        }
    }

    handleNavigateToMessage(event) {
        const messageId = event.detail?.messageId;
        if (!messageId) return;
        this.showSearch = false;
        this.template.querySelector('c-communicator-chat-timeline')
            ?.navigateToMessage(messageId);
    }

    handleMessageSent() {
        const timeline = this.template.querySelector('c-communicator-chat-timeline');
        timeline?.refresh().then(() => timeline?.scrollToBottom());
        markThreadAsRead({ threadId: this.threadId })
            .then(() => this._refreshGlobalUnreadCount())
            .catch(console.error);
        this.unreadCount = 0;
    }

    // ─────────────────────────────────────────
    // Config (inalterado)
    // ─────────────────────────────────────────

    async _loadConfig() {
        try {
            const settings = await getSettings();
            if (settings.hasCommunicatorChatPermission === false) {
                this._hasPermission       = false;
                this._noPermissionMessage = settings.noPermissionMessage || '';
                this._stopPolling();
                this._stopGlobalUnreadPolling();
                this._stopListPolling();
                return;
            }
            const previousPollingInterval = this._pollIntervalMs;
            if (settings.pollingIntervalMs >= MIN_POLL_MS) {
                this._pollIntervalMs = settings.pollingIntervalMs;
            }
            this._hasGroupAccess = settings.hasGroupAccess === true;
            this._isSalesforcePlatformUser = settings.isSalesforcePlatformUser === true;
            if (this._pollIntervalMs !== previousPollingInterval) {
                if (this.showChat) this._startPolling();
                this._startGlobalUnreadPolling();
                if (!this.showChat) this._startListPolling();
            }
        } catch (e) {
            this._hasPermission       = false;
            this._noPermissionMessage = 'Você não tem permissão para acessar as funcionalidades do canal de mensagens. Por favor, entre em contato com o Suporte de TI de vendas.';
            this._stopPolling();
            this._stopGlobalUnreadPolling();
            this._stopListPolling();
        }
    }

    // ─────────────────────────────────────────
    // Lista de threads (novo — mesma lógica do communicatorChatHistory)
    // ─────────────────────────────────────────

    async _loadThreadList(silent = false) {
        if (this.activeFilter === 'groups') return;
        if (!silent) this.isLoadingList = true;
        try {
            const useRecentCards = this.activeFilter === 'all' && !String(this.keyword || '').trim();
            const promises = [
                useRecentCards
                    ? getRecentlyViewedThreadCards({ maxCount: THREAD_PAGE_SIZE })
                    : getOpportunityChatList({ pageSize: THREAD_PAGE_SIZE, offsetVal: 0, filter: this.activeFilter, keyword: this.keyword }),
                getOpportunityChatCount({ filter: this.activeFilter, keyword: this.keyword }),
                getOpportunityUnreadMessageTotal({ pageSize: THREAD_PAGE_SIZE, offsetVal: 0, keyword: this.keyword }),
                getGlobalUnreadCount().catch(() => 0)
            ];
            const results = await Promise.all(promises);
            this._rawThreads     = results[0] || [];
            this.totalCount      = results[1] || 0;
            // O total por cards pode ignorar threads antigas com notificacao nao lida.
            // Usa o maior valor para o badge refletir as notificacoes reais do usuario.
            this._unreadTabCount = Math.max(results[2] || 0, results[3] || 0);
            this._isRecentCardList = useRecentCards;
            await this._refreshThreadPresenceOverrides();
            this._applyFilter();
            this._syncRecentStageCacheFromThreads();
            this._hydrateRecentStages().catch(() => {});
            this._hydrateThreadRelatedRefs().catch(() => {});
            this._queueThreadPresenceRefresh();
        } catch (e) {
            console.error('CommunicatorChatFloatingButton._loadThreadList:', e);
            this._rawThreads = [];
            this.threads     = [];
            this._isRecentCardList = false;
            this.threadPresenceStatusByUserId = {};
            this.threadPresenceOverrideByThreadId = {};
        } finally {
            if (!silent) this.isLoadingList = false;
            this._refreshBroadcastUnreadTotal();
        }
    }

    async _hydrateThreadRelatedRefs() {
        const ids = (this._rawThreads || [])
            .map(t => t?.recordId)
            .filter(id => id && String(id).startsWith('006'));
        await this._hydrateOpportunityRelatedRefs(ids);
    }

    async _hydrateOpportunityRelatedRefs(opportunityIds) {
        const uniqueIds = Array.from(new Set((opportunityIds || []).filter(Boolean)));
        const missingIds = uniqueIds.filter(id => !this.relatedRefsByOpportunityId?.[id]);
        if (missingIds.length === 0) return;

        const refsByOpportunityId = await getOpportunityRelatedRefs({ opportunityIds: missingIds });
        if (!refsByOpportunityId) return;

        this.relatedRefsByOpportunityId = {
            ...this.relatedRefsByOpportunityId,
            ...refsByOpportunityId
        };
        this._applyFilter();
    }

    _applyFilter() {
        // A busca por palavra-chave é feita no servidor (Apex), para suportar
        // Opportunity + Repasse (via Opportunity relacionada) sem perder registros no client.
        let result = [...this._rawThreads];

        if (this._etapaFilter) {
            result = result.filter(t => this._effectiveRecordType(t.recordType, t.hasRepasse) === this._etapaFilter);
        }
        if (this._stageFilters.length > 0) {
            result = result.filter(t => this._stageFilters.includes(this._getStageFilterValue(t)));
        }
        if (this.activeFilter === 'read') {
            result = result.filter(t => !!t?.threadId && !!String(t?.lastMessageAt || '').trim());
        }

        result = this._suppressOpportunityWhenRepasseExists(result);

        result = this._deduplicateThreadCards(result);
        if (this.activeFilter === 'all') {
            // "Todos": ordenado pelo card acessado mais recente (LastViewedDate via RecentlyViewed)
            // Cards não acessados ficam no final ordenados por lastMessageAt.
            const recentOrderSource = this._isRecentCardList
                ? (this._rawThreads || [])
                : (this.recentOpportunities || []);
            const recentThreadOrder = new Map(
                recentOrderSource
                    .map((record, idx) => record?.threadId ? [record.threadId, idx] : null)
                    .filter(Boolean)
            );
            const recentIdOrder = new Map(
                recentOrderSource
                    .map((record, idx) => {
                        const recordId = this._isRecentCardList
                            ? this._recentSortRecordId(record)
                            : record?.id;
                        return recordId ? [recordId, idx] : null;
                    })
                    .filter(Boolean)
            );
            result.sort((a, b) => {
                const aRecordId = this._recentSortRecordId(a);
                const bRecordId = this._recentSortRecordId(b);
                const aIdx = recentThreadOrder.has(a.threadId)
                    ? recentThreadOrder.get(a.threadId)
                    : (recentIdOrder.has(aRecordId) ? recentIdOrder.get(aRecordId) : Infinity);
                const bIdx = recentThreadOrder.has(b.threadId)
                    ? recentThreadOrder.get(b.threadId)
                    : (recentIdOrder.has(bRecordId) ? recentIdOrder.get(bRecordId) : Infinity);
                if (aIdx !== bIdx) return aIdx - bIdx;
                return this._parseListDateTime(b.lastMessageAt) - this._parseListDateTime(a.lastMessageAt);
            });
        } else if (this.activeFilter === 'read') {
            // "Lidos": ordenado por quando o usuário leu a última notificação (ReadAt__c).
            // Só muda ao ir de não lido → lido; abrir um card já lido não altera a posição.
            result.sort((leftRecord, rightRecord) =>
                this._parseListDateTime(rightRecord?.lastReadAt) - this._parseListDateTime(leftRecord?.lastReadAt)
            );
        } else {
            result.sort((leftRecord, rightRecord) => {
                const leftUnread  = (leftRecord?.unreadCount  || 0) > 0;
                const rightUnread = (rightRecord?.unreadCount || 0) > 0;
                if (leftUnread !== rightUnread) return leftUnread ? -1 : 1;
                return this._parseListDateTime(rightRecord?.lastMessageAt) - this._parseListDateTime(leftRecord?.lastMessageAt);
            });
        }
        this.threads = result;
    }

    _suppressOpportunityWhenRepasseExists(records) {
        const repasseThreadIds = new Set(
            records
                .filter(r => r?.recordType === 'Repasse__c' && !!r?.threadId)
                .map(r => r.threadId)
        );

        if (repasseThreadIds.size === 0) return records;

        return records.filter(r => !(r?.recordType === 'Opportunity' && repasseThreadIds.has(r?.threadId)));
    }

    _buildListCardKey(record) {
        if (record?.threadId) return `thread:${record.threadId}`;
        if (record?.recordId) return `record:${record.recordId}`;
        return null;
    }

    _resolveSelectedThreadCard(recordId, objectType, threadId) {
        if (!recordId) return null;
        const normalizedType = this._effectiveRecordType(objectType || 'Opportunity', objectType === 'Repasse__c');
        const allCards = [...(this.threads || []), ...(this._rawThreads || [])];
        if (threadId) {
            const cardByThread = allCards.find(card => card?.threadId === threadId);
            if (cardByThread) return cardByThread;
        }
        const cardByRecordAndType = allCards.find(card =>
            card?.recordId === recordId &&
            this._effectiveRecordType(card?.recordType, card?.hasRepasse) === normalizedType
        );
        if (cardByRecordAndType) return cardByRecordAndType;
        return allCards.find(card => card?.recordId === recordId) || null;
    }

    _deduplicateThreadCards(records) {
        const uniqueRecords = [];
        const indexByKey = new Map();
        for (const record of (records || [])) {
            const key = this._buildListCardKey(record);
            if (!key) continue;
            if (!indexByKey.has(key)) {
                indexByKey.set(key, uniqueRecords.length);
                uniqueRecords.push(record);
                continue;
            }
            const existingIndex = indexByKey.get(key);
            uniqueRecords[existingIndex] = this._selectPreferredThreadCard(uniqueRecords[existingIndex], record);
        }
        return uniqueRecords;
    }

    _selectPreferredThreadCard(currentRecord, candidateRecord) {
        const currentHasRelatedRef = this._cardHasResolvedRelatedRef(currentRecord);
        const candidateHasRelatedRef = this._cardHasResolvedRelatedRef(candidateRecord);
        if (candidateHasRelatedRef !== currentHasRelatedRef) {
            return candidateHasRelatedRef ? candidateRecord : currentRecord;
        }
        const currentIsOpportunity = String(currentRecord?.recordId || '').startsWith('006');
        const candidateIsOpportunity = String(candidateRecord?.recordId || '').startsWith('006');
        if (candidateIsOpportunity !== currentIsOpportunity) {
            return candidateIsOpportunity ? candidateRecord : currentRecord;
        }
        return currentRecord;
    }

    _cardHasResolvedRelatedRef(recordInfo) {
        if (!recordInfo?.recordId) return false;
        const relatedRefs = this.relatedRefsByOpportunityId?.[recordInfo.recordId];
        const relatedRef = this._buildCompactRelatedRef(recordInfo, relatedRefs);
        return !!relatedRef?.name;
    }

    _pickCompactThreadId(recordThreads, recordType) {
        const threads = Array.isArray(recordThreads) ? recordThreads : [];
        if (threads.length === 0) return null;

        const isRepasseType = recordType === 'Repasse__c';
        for (let i = threads.length - 1; i >= 0; i -= 1) {
            const stageName = threads[i]?.stageName;
            const isRepasseStage = this._isRepasseMacroPhase(stageName);
            if ((isRepasseType && isRepasseStage) || (!isRepasseType && !isRepasseStage)) {
                return threads[i]?.threadId || null;
            }
        }

        return null;
    }

    _isRepasseMacroPhase(stageName) {
        const normalized = this._normalizeStatusKey(stageName);
        return REPASSE_MACRO_PHASES.has(normalized);
    }

    // ─────────────────────────────────────────
    // Polling (inalterado)
    // ─────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        this._pollTimer = setInterval(async () => {
            this.template.querySelector('c-communicator-chat-timeline')?.refresh();

            if (this.opportunityId) {
                try {
                    const [liveOppStage, repassePhase] = await Promise.all([
                        getRecordCurrentStage({ recordId: this.opportunityId, objectType: 'Opportunity' }),
                        getRepasseMacroPhaseByOppId({ opportunityId: this.opportunityId })
                    ]);
                    const effectiveStage = repassePhase || liveOppStage || '';
                    if (effectiveStage && effectiveStage !== this._chatCurrentStage) {
                        this._chatCurrentStage = effectiveStage;
                        const updatedThread = await getOrCreateThread({ recordId: this.opportunityId, objectType: 'Opportunity' });
                        if (updatedThread?.Id && updatedThread.Id !== this.threadId) {
                            this.threadId = updatedThread.Id;
                            if (!this.chatThreadIds.includes(updatedThread.Id)) {
                                this.chatThreadIds = [...this.chatThreadIds, updatedThread.Id];
                            }
                            markThreadAsRead({ threadId: updatedThread.Id }).catch(() => {});
                            this.unreadCount = 0;
                        }
                    }
                } catch (e) { /* silent */ }
            }

            const threadsToCount = this.chatThreadIds.length > 0
                ? this.chatThreadIds
                : (this.threadId ? [this.threadId] : []);
            if (threadsToCount.length > 0) {
                try {
                    const unreadByThread = await Promise.all(
                        threadsToCount.map(threadId => getUnreadCount({ threadId }))
                    );
                    this.unreadCount = unreadByThread.reduce((sum, count) => sum + (count || 0), 0);
                } catch (e) { /* silent */ }
            }
        }, this._pollIntervalMs);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    _startGlobalUnreadPolling() {
        this._stopGlobalUnreadPolling();
        this._globalUnreadPollTimer = setInterval(() => {
            this._refreshGlobalUnreadCount().catch(() => {});
            this._refreshBroadcastUnreadTotal();
        }, this._pollIntervalMs);
    }

    _stopGlobalUnreadPolling() {
        if (!this._globalUnreadPollTimer) return;
        clearInterval(this._globalUnreadPollTimer);
        this._globalUnreadPollTimer = null;
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
            console.error('[communicatorChatFloatingButton] _refreshBroadcastUnreadTotal:', e);
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

    _startListPolling() {
        this._stopListPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._listPollTimer = setInterval(() => {
            if (this.showChat) return;
            if (this.isBroadcastPrimary) {
                this._refreshBroadcastUnreadTotal();
                this.template.querySelector('c-communicator-broadcast-workspace')?.refresh();
                return;
            }
            if (!this.isLoadingThread) this._refreshRecents().catch(() => {});
            if (this.activeFilter === 'groups') {
                this._loadGroups(true).catch(() => {});
            } else {
                this._loadThreadList(true).catch(() => {});
                this._loadGroups(true).catch(() => {});
            }
        }, this._pollIntervalMs);
    }

    _stopListPolling() {
        if (!this._listPollTimer) return;
        clearInterval(this._listPollTimer);
        this._listPollTimer = null;
    }

    _clearBroadcastImagePreview() {
        this.broadcastImagePreview = null;
        this._broadcastImagePreviewReturnFocus = null;
        this._isBroadcastImagePreviewModalPending = false;
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

    _finalizeUtilityBroadcastImagePreview() {
        this.broadcastImagePreview = null;
        this.template.querySelector('c-communicator-broadcast-workspace')?.notifyImagePreviewClosed?.();
        this._restoreBroadcastImagePreviewFocus();
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
        return this.template.querySelector('[data-view="broadcast"]');
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

    async _refreshGlobalUnreadCount() {
        try {
            const totalUnreadCount = await getGlobalUnreadCount();
            this.globalUnreadCount = totalUnreadCount || 0;
        } catch (error) {
            // Keep last known value on fetch failures.
        }
    }

    // ─────────────────────────────────────────
    // Recent opportunities (RecentlyViewed nativo via CommunicatorThread__c)
    // ─────────────────────────────────────────

    async _refreshRecents() {
        try {
            const recents = await getRecentlyViewedThreads({ maxCount: MAX_RECENT });
            this.recentOpportunities = (recents || []).map(r => ({
                id: r.id,
                name: r.name,
                threadId: r.threadId || null
            }));
            if (!this.showChat && this.activeFilter === 'all') {
                this._applyFilter();
            }
            this._hydrateRecentRelatedRefs();
            this._hydrateRecentStages().catch(() => {});
        } catch (e) { /* silent */ }
    }

    async _hydrateRecentRelatedRefs() {
        const missingIds = (this.recentOpportunities || [])
            .filter(r => r?.id && r.id.startsWith('006'))
            .map(r => r.id);

        if (missingIds.length === 0) return;

        try {
            await this._hydrateOpportunityRelatedRefs(missingIds);
        } catch (e) { /* silent */ }
    }

    _hasRecentStageCache(opportunityId) {
        return Object.prototype.hasOwnProperty.call(this.recentStageByOpportunityId || {}, opportunityId);
    }

    _syncRecentStageCacheFromThreads() {
        const stageByOpportunityId = {};
        for (const recentRecord of (this.recentOpportunities || [])) {
            const opportunityId = recentRecord?.id;
            if (!opportunityId || this._hasRecentStageCache(opportunityId)) continue;
            const threadRecord = this._rawThreads.find(thread => thread?.recordId === opportunityId);
            const stageValue = threadRecord?.currentStage || threadRecord?.stageName || '';
            if (!stageValue) continue;
            stageByOpportunityId[opportunityId] = stageValue;
        }
        if (Object.keys(stageByOpportunityId).length === 0) return;
        this.recentStageByOpportunityId = {
            ...this.recentStageByOpportunityId,
            ...stageByOpportunityId
        };
    }

    _buildRecentStageRequests() {
        const requests = [];
        for (const recentRecord of (this.recentOpportunities || [])) {
            const opportunityId = recentRecord?.id;
            if (!opportunityId || !String(opportunityId).startsWith('006')) continue;
            if (this._hasRecentStageCache(opportunityId)) continue;
            const threadRecord = this._rawThreads.find(thread => thread?.recordId === opportunityId);
            const stageValue = threadRecord?.currentStage || threadRecord?.stageName || '';
            if (stageValue) continue;
            requests.push(
                getRecordCurrentStage({ recordId: opportunityId, objectType: 'Opportunity' })
                    .then(currentStageValue => ({
                        opportunityId,
                        currentStageValue
                    }))
            );
        }
        return requests;
    }

    _applyRecentStageResults(stageResults) {
        const stageByOpportunityId = {};
        for (const stageResult of (stageResults || [])) {
            const opportunityId = stageResult?.opportunityId;
            if (!opportunityId || this._hasRecentStageCache(opportunityId)) continue;
            stageByOpportunityId[opportunityId] = stageResult?.currentStageValue || '';
        }
        if (Object.keys(stageByOpportunityId).length === 0) return;
        this.recentStageByOpportunityId = {
            ...this.recentStageByOpportunityId,
            ...stageByOpportunityId
        };
    }

    async _hydrateRecentStages() {
        this._syncRecentStageCacheFromThreads();
        const stageRequests = this._buildRecentStageRequests();
        if (stageRequests.length === 0) return;
        const stageResults = await Promise.all(stageRequests);
        this._applyRecentStageResults(stageResults);
    }

    // ─────────────────────────────────────────
    // Computed existentes (inalterados)
    // ─────────────────────────────────────────

    get accessOpportunityLabel() {
        return this._isSalesforcePlatformUser ? 'Acessar Repasse' : 'Acessar oportunidade';
    }

    get hasCompactOpportunityContext() {
        return this.showChat
            && typeof this.opportunityId === 'string'
            && this.opportunityId.startsWith('006');
    }

    get canShowCompactChatterToggle() {
        return this.hasCompactOpportunityContext
            && typeof this.threadId === 'string'
            && this.threadId.length > 0;
    }

    get showCompactChatterSection() {
        return this.canShowCompactChatterToggle && this.showChatterHistory;
    }

    get showCompactStandardTimeline() {
        return !this.showCompactChatterSection;
    }

    get isCompactComposerDisabled() {
        return this.showCompactChatterSection;
    }

    get canNavigateChatterFiles() {
        return !this._isBrokerCommunityContext();
    }

    get compactChatterToggleLabel() {
        return this.showCompactChatterSection
            ? 'Ocultar histórico Chatter'
            : 'Exibir histórico Chatter';
    }

    get compactSearchPlaceholder() {
        return this.showCompactChatterSection
            ? 'Buscar no Chatter...'
            : 'Buscar mensagens...';
    }

    get isFabMode() {
        return (this.mode || MODE_FAB) === MODE_FAB;
    }

    get isUtilityMode() {
        return this.mode === MODE_UTILITY;
    }

    get showPanel() {
        return this.isUtilityMode || this.isOpen;
    }

    get showBroadcastImagePreview() {
        return !this.isUtilityMode && !!this.broadcastImagePreview?.src;
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

    get panelClass() {
        if (this.isUtilityMode) {
            return this.mobileMode ? 'comm-utility-panel comm-mobile-panel' : 'comm-utility-panel';
        }
        return this.showChat || this.isBroadcastCommunityTimelineContext
            ? 'comm-fab-panel comm-fab-panel--chat'
            : 'comm-fab-panel comm-fab-panel--list';
    }

    get isBroadcastCommunityContext() {
        return this.activePrimaryView === PRIMARY_VIEW_BROADCAST && this._isBrokerCommunityContext();
    }

    get isBroadcastCommunityTimelineContext() {
        return this.isBroadcastCommunityContext && this.isBroadcastTimelineOpen;
    }

    get fabClass() {
        return ['comm-fab', this.isOpen ? 'comm-fab--active' : ''].join(' ').trim();
    }

    get fabIcon() {
        return this.isOpen ? 'utility:close' : 'utility:chat';
    }

    get hasRecent() {
        return this.recentOpportunities && this.recentOpportunities.length > 0;
    }

    get showUnreadBadge() {
        return this.isFabMode && (this.liveNotificationCount > 0 || this.totalUnreadCount > 0);
    }

    get totalUnreadCount() {
        return (this.globalUnreadCount || 0) + (this.broadcastUnreadTotal || 0);
    }

    get displayUnread() {
        const badgeCount = this.liveNotificationCount > 0
            ? this.liveNotificationCount
            : this.totalUnreadCount;
        return badgeCount > 99 ? '99+' : String(badgeCount);
    }

    get fabBadgeClass() {
        const badgeClassName = this.liveNotificationCount > 0
            ? 'comm-fab-badge--live'
            : 'comm-fab-badge--unread';
        return `comm-fab-badge ${badgeClassName}`;
    }

    get hasLiveNotificationBadge() {
        return this.liveNotificationCount > 0;
    }

    get liveNotificationBadgeText() {
        return this.liveNotificationCount > 99 ? '99+' : String(this.liveNotificationCount);
    }

    get liveNotificationTooltip() {
        if (!this.liveNotificationTargetRecordName) return 'Nova marcação recebida';
        return `Última marcação: ${this.liveNotificationTargetRecordName}`;
    }

    get opportunityFilter() {
        return {
            criteria: [
                { fieldPath: 'IsClosed', operator: 'eq', value: false }
            ]
        };
    }

    // ─────────────────────────────────────────
    // Computed da lista de threads (novo)
    // ─────────────────────────────────────────

    get tabs() {
        const unreadBadge = this._unreadTabCount > 99 ? '99+' : String(this._unreadTabCount);
        const totalGroupUnread = this._groups.reduce((s, g) => s + (g.unreadMentionCount || 0), 0);
        const groupBadge = totalGroupUnread > 99 ? '99+' : String(totalGroupUnread);
        const isBroadcastActive = this.activePrimaryView === PRIMARY_VIEW_BROADCAST;
        const all = [
            { key: 'all',    filter: 'all',    label: 'Todos',     view: null, tabClass: this._tabClass('all'),    showBadge: false,                    badgeLabel: '',          badgeClass: 'comm-picker__tab-badge' },
            { key: 'read',   filter: 'read',   label: 'Lidos',     view: null, tabClass: this._tabClass('read'),   showBadge: false,                    badgeLabel: '',          badgeClass: 'comm-picker__tab-badge' },
            { key: 'unread', filter: 'unread', label: 'Não lidos', view: null, tabClass: this._tabClass('unread'), showBadge: this._unreadTabCount > 0, badgeLabel: unreadBadge, badgeClass: 'comm-picker__tab-badge' },
            { key: 'groups', filter: 'groups', label: 'Grupos',    view: null, tabClass: this._tabClass('groups'), showBadge: totalGroupUnread > 0,     badgeLabel: groupBadge,  badgeClass: 'comm-picker__tab-badge' },
            {
                key: 'broadcast',
                filter: null,
                label: 'Comunicados',
                view: PRIMARY_VIEW_BROADCAST,
                tabClass: isBroadcastActive
                    ? 'comm-picker__tab comm-picker__tab--broadcast comm-picker__tab--active'
                    : 'comm-picker__tab comm-picker__tab--broadcast',
                showBadge: this.hasBroadcastUnread,
                badgeLabel: this.broadcastBadgeLabel,
                accessibilityLabel: this.broadcastBadgeAccessibilityLabel,
                badgeClass: this.broadcastBadgeClass
            }
        ];
        return all;
    }

    get showConversationPrimary() {
        return this.activePrimaryView === PRIMARY_VIEW_CONVERSATIONS;
    }

    get showBroadcastPrimary() {
        return this.activePrimaryView === PRIMARY_VIEW_BROADCAST;
    }

    get isBroadcastPrimary() {
        return this.showBroadcastPrimary;
    }

    get showGroupList()   { return this.activeFilter === 'groups' && !this._inGroupView; }
    get showGroupView()   { return this.activeFilter === 'groups' && this._inGroupView; }
    get hasGroups()       { return this._groups && this._groups.length > 0; }
    get hasNoGroups()     { return !this.hasGroups; }

    get enrichedThreads() {
        return this.threads.map(t => {
            const relatedRefs = this.relatedRefsByOpportunityId?.[t.recordId];
            const displayStatus = this._buildDisplayStatusData(t, relatedRefs);
            const relatedRef = this._buildCompactRelatedRef(t, relatedRefs);
            const typeRecord = this._buildTypeBadgeData(t.recordType, t.hasRepasse);
            const effectiveRecordType = this._effectiveRecordType(t.recordType, t.hasRepasse);
            const presenceContext = this._resolveThreadPresenceContext(t);
            const presenceStatus = this._resolveThreadPresenceStatus(
                presenceContext.userId,
                presenceContext.statusOverride,
                presenceContext.rawUserId
            );
            return {
                ...t,
                recordName:      this._resolveThreadDisplayName(t),
                displayStatus:    displayStatus.value,
                displayStatusLabel: displayStatus.label,
                stageClass:      displayStatus.className,
                effectiveRecordType,
                typeLabel:       typeRecord.label,
                typeClass:       typeRecord.className,
                unreadText:      this._unreadText(t.unreadCount),
                showUnreadBadge: t.unreadCount > 0,
                listKey: this._buildListCardKey(t) || t.recordId || t.recordName,
                relatedRefId: relatedRef?.id || null,
                relatedRefName: relatedRef?.name || '',
                relatedRefType: relatedRef?.type || null,
                relatedRefObjectApiName: relatedRef?.objectApiName || null,
                showRelatedRef: !!relatedRef?.name,
                isRelatedRefClickable: !!relatedRef?.id,
                showPresenceStatus: !!presenceContext.userId && presenceStatus === 'online',
                presenceDotClass: `comm-picker__presence-dot comm-picker__presence-dot--${presenceStatus}`,
                presenceLabel: this._socketStatusLabel(presenceStatus),
                unreadAriaLabel: t.unreadCount === 1
                    ? '1 mensagem não lida'
                    : `${t.unreadCount} mensagens não lidas`,
                lastMessageDisplay: t.lastMessageAt || 'Conversa não iniciada',
                lastMessageDateClass: t.lastMessageAt
                    ? 'comm-picker__conv-date'
                    : 'comm-picker__conv-date comm-picker__conv-date--empty'
            };
        });
    }

    get displayedThreads() {
        if (!this.showRecentSection) return this.enrichedThreads;
        const recentIds = new Set(
            this.enrichedRecents
                .map(recentRecord => recentRecord?.id)
                .filter(Boolean)
        );
        if (recentIds.size === 0) return this.enrichedThreads;
        return this.enrichedThreads.filter(threadCard => !recentIds.has(threadCard.recordId));
    }

    get hasThreads()  { return this.displayedThreads.length > 0; }
    get isListEmpty() {
        if (this.activeFilter === 'groups' || this.isLoadingList) return false;
        if (this.showRecentSection && this.enrichedRecents.length > 0) return false;
        return this.displayedThreads.length === 0;
    }
    get showRecents() { return false; }

    get showRecentSection() {
        return false;
    }

    get enrichedRecents() {
        return this.recentOpportunities.map(opp => {
            const thread = this._rawThreads.find(t => t.recordId === opp.id);
            const recentStageValue = thread?.currentStage
                || thread?.stageName
                || this.recentStageByOpportunityId?.[opp.id]
                || '';
            const presenceContext = this._resolveThreadPresenceContext(thread || {});
            const presenceStatus = this._resolveThreadPresenceStatus(
                presenceContext.userId,
                presenceContext.statusOverride,
                presenceContext.rawUserId
            );
            const recentRecord = thread || {
                recordId: opp.id,
                recordType: 'Opportunity',
                hasRepasse: false,
                currentStage: recentStageValue,
                stageName: recentStageValue,
                displayStatus: recentStageValue
            };
            const relatedRefs = this.relatedRefsByOpportunityId?.[opp.id];
            const displayStatus = this._buildDisplayStatusData(recentRecord, relatedRefs);
            const relatedRef = this._buildCompactRelatedRef(recentRecord, relatedRefs);
            const typeRecord = this._buildTypeBadgeData(recentRecord.recordType, recentRecord.hasRepasse);
            const effectiveRecordType = this._effectiveRecordType(
                recentRecord.recordType,
                recentRecord.hasRepasse
            );
            return {
                id:           opp.id,
                name:         this._resolveRecentDisplayName(opp),
                lastMessageAt: thread ? thread.lastMessageAt : null,
                threadId:     thread?.threadId || null,
                effectiveRecordType,
                displayStatus: displayStatus.value,
                displayStatusLabel: displayStatus.label,
                stageClass:   displayStatus.className,
                typeLabel:    typeRecord.label,
                typeClass:    typeRecord.className,
                threadName:   thread ? thread.threadName : null,
                showUnreadBadge: thread ? thread.unreadCount > 0 : false,
                unreadText:   thread ? this._unreadText(thread.unreadCount) : '',
                relatedRefId: relatedRef?.id || null,
                relatedRefName: relatedRef?.name || '',
                relatedRefType: relatedRef?.type || null,
                relatedRefObjectApiName: relatedRef?.objectApiName || null,
                showRelatedRef: !!relatedRef?.name,
                isRelatedRefClickable: !!relatedRef?.id,
                showPresenceStatus: false,
                presenceDotClass: `comm-picker__presence-dot comm-picker__presence-dot--${presenceStatus}`,
                presenceLabel: this._socketStatusLabel(presenceStatus),
                unreadAriaLabel: thread
                    ? (thread.unreadCount === 1 ? '1 mensagem não lida' : `${thread.unreadCount} mensagens não lidas`)
                    : '',
                lastMessageDisplay: thread?.lastMessageAt || 'Conversa não iniciada',
                lastMessageDateClass: thread?.lastMessageAt
                    ? 'comm-picker__conv-date'
                    : 'comm-picker__conv-date comm-picker__conv-date--empty'
            };
        }).filter(opp => {
            const thread = this._rawThreads.find(t => t.recordId === opp.id);
            const recentStageValue = thread?.currentStage
                || thread?.stageName
                || this.recentStageByOpportunityId?.[opp.id]
                || '';
            const filterRecord = thread || {
                recordType: 'Opportunity',
                hasRepasse: false,
                currentStage: recentStageValue,
                stageName: recentStageValue
            };
            if (this._etapaFilter && this._effectiveRecordType(filterRecord.recordType, filterRecord.hasRepasse) !== this._etapaFilter) {
                return false;
            }
            if (this._stageFilters.length === 0) return true;
            return this._stageFilters.includes(this._getStageFilterValue(filterRecord));
        }).sort((a, b) => {
            const aUnread = a.showUnreadBadge || false;
            const bUnread = b.showUnreadBadge || false;
            if (aUnread !== bUnread) return aUnread ? -1 : 1;
            return this._parseListDateTime(b.lastMessageAt) - this._parseListDateTime(a.lastMessageAt);
        });
    }

    get hasActiveFilter() {
        return !!(this._etapaFilter || this._stageFilters.length > 0);
    }

    get filterBtnClass() {
        return this.hasActiveFilter
            ? 'comm-picker__filter-btn comm-picker__filter-btn--active'
            : 'comm-picker__filter-btn';
    }

    get etapaOptions() {
        return [
            { label: 'Todos', value: '' },
            { label: 'Oportunidade', value: 'Opportunity' },
            { label: 'Repasse', value: 'Repasse__c' }
        ];
    }

    get stageOptions() {
        if (this._etapaFilter === 'Opportunity') return this._buildStageOptionsForType('Opportunity');
        if (this._etapaFilter === 'Repasse__c') return this._buildStageOptionsForType('Repasse__c');
        return [
            ...this._buildStageOptionsForType('Opportunity'),
            ...this._buildStageOptionsForType('Repasse__c')
        ];
    }

    get hasStageOptions() { return this.stageOptions.length > 0; }

    _tabClass(filter) {
        const base = 'comm-picker__tab';
        if (this.activePrimaryView !== PRIMARY_VIEW_CONVERSATIONS) return base;
        return filter === this.activeFilter ? `${base} ${base}--active` : base;
    }

    _buildStageOptionsForType(recordType) {
        const source = this._rawThreads.filter(t => this._effectiveRecordType(t.recordType, t.hasRepasse) === recordType);
        if (recordType === 'Repasse__c') {
            return REPASSE_FILTER_OPTIONS.map(config => ({
                label: config.label,
                value: config.value,
                checked: this._stageFilters.includes(config.value),
                count: source.filter(t => this._getRepasseFilterValue(t) === config.value).length
            }));
        }

        const optionDefs = OPPORTUNITY_FILTER_OPTIONS;

        return optionDefs.map(opt => ({
            label: opt.label,
            value: opt.value,
            checked: this._stageFilters.includes(opt.value),
            count: source.filter(t => this._getStageFilterValue(t) === opt.value).length
        }));
    }

    _getStageFilterValue(recordInfo) {
        const effectiveType = this._effectiveRecordType(recordInfo?.recordType, recordInfo?.hasRepasse);
        return effectiveType === 'Repasse__c'
            ? this._getRepasseFilterValue(recordInfo)
            : this._getOpportunityFilterValue(recordInfo);
    }

    _getRepasseFilterValue(recordInfo) {
        const normalizedMacroPhase = this._normalizeStatusKey(recordInfo?.currentStage || recordInfo?.displayStatus || '');
        const macroPhaseFilterValue = REPASSE_FILTER_VALUE_BY_MACRO_PHASE[normalizedMacroPhase];
        if (macroPhaseFilterValue) return macroPhaseFilterValue;

        const normalizedStatus = this._normalizeStatusKey(recordInfo?.rawRepasseStatus || recordInfo?.displayStatus || '');
        const groupedFilterValue = this._matchRepasseFilterGroup(normalizedStatus);
        if (groupedFilterValue) return groupedFilterValue;
        return normalizedStatus ? 'repasse_outros' : '';
    }

    _matchRepasseFilterGroup(normalizedStatus) {
        if (!normalizedStatus) return '';

        const repasseGroups = {
            repasse_aguardando_inicio: [
                'IR FUTURO',
                'ASSINATURA DE FORMULÁRIOS',
                'AGUARDANDO PJ',
                'SFH',
                'VENDA DIRETA',
                'AGUARDANDO ENCERRAMENTO DE OBRA'
            ],
            repasse_formulario: [
                'AGENDADO',
                'DÉBITO DO FGTS',
                'AGENDAR ENTREVISTA MANUAL',
                'VENDA NOVA'
            ],
            repasse_conferencia_dossie: [
                'MONTAGEM CEHOP',
                'CONFERÊNCIA'
            ],
            repasse_pendencias: [
                'PENDÊNCIA PARA ENVIO',
                'INCONFORME',
                'AGUARDANDO DOCUMENTOS',
                'REAPROVAÇÃO DE CRÉDITO',
                'ANÁLISE JURÍDICA',
                'REANÁLISE JURÍDICA'
            ],
            repasse_assinatura_repasse: [
                'FECHAMENTO DE VALORES',
                'APTO PARA ASSINATURA',
                'AGENDAR ASSINATURA MANUAL',
                'ASSINATURA AGENDADA',
                'PENDENCIA CONFERENCIA EXTERNA',
                'ASSINADO PENDENCIA SANADA',
                'ASSINADO COM PENDÊNCIA',
                'ASSINADO EM CONFERÊNCIA',
                'FASE (CONFERÊNCIA) SÍNTESE (CONFERÊNCIA EXTERNA)',
                'ASSINATURA PENDÊNCIA SANADA',
                'ASSINATURA BANCO',
                'ASSINATURA DIGITAL',
                'ASSINATURA FÍSICO',
                'FASE (REGISTRO) SÍNTESE (AGUARDANDO REGISTRO)',
                'FASE (REGISTRADO) SÍNTESE (CONTRATO CONFORME)'
            ],
            repasse_retencao: [
                'TROCA RETENÇÃO',
                'TROCA COMERCIAL',
                'EM NEGOCIAÇÃO',
                'FAZER CONTATO',
                'POSSÍVEL CESSÃO',
                'FASE (RETENÇÃO REPASSE) - SÍNTESE (TROCA RETENÇÃO)',
                'FASE (RETENÇÃO REPASSE) - SÍNTESE (TROCA COMERCIAL)',
                'FASE (RETENÇÃO REPASSE) - SÍNTESE (EM NEGOCIAÇÃO)',
                'FASE (RETENÇÃO REPASSE) - SÍNTESE (FAZER CONTATO)',
                'FASE (RETENÇÃO REPASSE) - SÍNTESE (POSSÍVEL CESSÃO)'
            ],
            repasse_triagem: [
                'SEM CONTATO',
                'CESSÃO CONCLUÍDA',
                'RETORNO',
                'RETORNO DA RETENÇÃO',
                'RESTRIÇÃO',
                'RESTRIÇÃO SERASA/RF',
                'SEM INTERESSE',
                'SEM INTERESSE NO REPASSE',
                'NÃO ENQUADRADO',
                'NÃO LOCALIZADO',
                'FASE (RETENÇÃO REPASSE) - SÍNTESE (SEM CONTATO)',
                'FASE (TRIAGEM) - SÍNTESE (CESSÃO CONCLUÍDA)',
                'FASE (TRIAGEM) - SÍNTESE (RETORNO DA RETENÇÃO)',
                'FASE (TRIAGEM) - SÍNTESE (RESTRIÇÃO SERASA/RF)',
                'FASE (TRIAGEM) - SÍNTESE (SEM INTERESSE NO REPASSE)',
                'FASE (TRIAGEM) - SÍNTESE (NÃO ENQUADRADO)',
                'FASE (TRIAGEM) - SÍNTESE (NÃO LOCALIZADO)'
            ]
        };

        for (const [groupKey, values] of Object.entries(repasseGroups)) {
            const normalizedValues = values.map(value => this._normalizeStatusKey(value));
            if (normalizedValues.includes(normalizedStatus)) {
                return groupKey;
            }
        }

        return '';
    }

    _getOpportunityFilterValue(recordInfo) {
        const status = this._normalizeStatusKey(recordInfo?.currentStage || recordInfo?.stageName || '');

        if (
            status.includes('montagem de pasta') ||
            status.includes('montagem')
        ) {
            return 'opportunity_montagem_pasta';
        }

        if (
            status.includes('analise de renda') ||
            status.includes('apuracao de renda')
        ) {
            return 'opportunity_analise_renda';
        }

        if (
            status.includes('analise de credito') ||
            status.includes('cotacao') ||
            status.includes('cotacoes') ||
            status.includes('aprovacao bancaria')
        ) {
            return 'opportunity_analise_credito';
        }

        if (
            status.includes('negoci')
        ) {
            return 'opportunity_negociacao';
        }

        if (
            status.includes('condicao credito') ||
            status.includes('condicao de credito') ||
            status.includes('aprovacao da condicao credito')
        ) {
            return 'opportunity_condicao_credito';
        }

        if (
            status.includes('condicao comercial') ||
            status.includes('comercial')
        ) {
            return 'opportunity_condicao_comercial';
        }

        if (
            status.includes('contrato') &&
            !status.includes('assinado') &&
            !status.includes('ganha')
        ) {
            return 'opportunity_contrato';
        }

        if (
            status.includes('assinado') ||
            status.includes('ganha') ||
            status.includes('desembolsado')
        ) {
            return 'opportunity_ganha';
        }

        return '';
    }

    _buildCompactRelatedRef(recordInfo, relatedRefs) {
        const refs = relatedRefs || {};
        const effectiveType = this._effectiveRecordType(recordInfo?.recordType, recordInfo?.hasRepasse);
        if (effectiveType !== 'Opportunity') return null;

        if (refs.resolvedRefId && refs.resolvedRefName) {
            const resolvedRefName = this._isQuoteReference(refs.resolvedRefType, refs.resolvedRefObjectApiName)
                ? this._formatQuoteRelatedRefName(refs.resolvedRefName)
                : refs.resolvedRefName;
            return this._newRelatedRef(
                refs.resolvedRefType,
                refs.resolvedRefId,
                resolvedRefName,
                refs.resolvedRefObjectApiName
            );
        }

        const stageType = this._getOpportunityFilterValue(recordInfo || {});
        let relatedRef = null;
        if (stageType === 'opportunity_negociacao') {
            relatedRef = this._newRelatedRef('quote', refs.quoteId, this._formatQuoteRelatedRefName(refs.quoteName));
        }
        if (!relatedRef && stageType === 'opportunity_analise_credito') {
            relatedRef = this._newRelatedRef('ab', refs.abId, refs.abName);
            if (!relatedRef) {
                relatedRef = this._newRelatedRef('ar', refs.arId, refs.arName);
            }
        }
        if (!relatedRef && (stageType === 'opportunity_montagem_pasta' || stageType === 'opportunity_analise_renda')) {
            if (refs.abId && refs.abName) {
                relatedRef = this._newRelatedRef('ab', refs.abId, refs.abName);
            } else {
                relatedRef = this._newRelatedRef('ar', refs.arId, refs.arName);
            }
        }
        return relatedRef || this._buildNotFoundRelatedRef(stageType);
    }

    _buildNotFoundRelatedRef(stageType) {
        const notFoundLabel = RELATED_REF_NOT_FOUND_LABEL_BY_STAGE[stageType];
        if (!notFoundLabel) return null;
        return {
            type: 'not_found',
            id: null,
            name: notFoundLabel,
            objectApiName: null
        };
    }

    _newRelatedRef(type, id, name, objectApiName) {
        if (!id || !name) return null;
        return {
            type,
            id,
            name,
            objectApiName: objectApiName || this._objectApiNameByRelatedRefType(type)
        };
    }

    _isQuoteReference(referenceType, objectApiName) {
        return referenceType === 'quote' || objectApiName === 'Quote';
    }

    _formatQuoteRelatedRefName(quoteName) {
        if (!quoteName) return '';
        return `Cotação-${quoteName}`;
    }

    _buildQuoteCountStatus(quoteCount) {
        if (quoteCount === 1) return '1 cotação';
        return `${quoteCount} cotações`;
    }

    _stageClass(stage) {
        if (!stage) return 'comm-picker__badge comm-picker__badge--default';
        const normalized = this._normalizeStatusKey(stage);
        if (normalized.includes('cotac')) {
            return 'comm-picker__badge comm-picker__badge--indigo-soft';
        }
        if (normalized.includes('apura')) {
            return 'comm-picker__badge comm-picker__badge--orange';
        }
        if (normalized.includes('negocia') || normalized.includes('anali')) {
            return 'comm-picker__badge comm-picker__badge--blue';
        }
        if (normalized.includes('monta') || normalized.includes('pasta')) {
            return 'comm-picker__badge comm-picker__badge--yellow';
        }
        if (normalized.includes('aprovad') || normalized.includes('confor')) {
            return 'comm-picker__badge comm-picker__badge--green';
        }
        if (normalized.includes('reprovad') || normalized.includes('cancel')) {
            return 'comm-picker__badge comm-picker__badge--red';
        }
        if (
            normalized.includes('aguard')
            || normalized.includes('repasse')
            || normalized.includes('formu')
            || normalized.includes('outro')
            || normalized.includes('doss')
            || normalized.includes('pend')
            || normalized.includes('assin')
            || normalized.includes('reten')
            || normalized.includes('triag')
        ) {
            return 'comm-picker__badge comm-picker__badge--blue';
        }
        return 'comm-picker__badge comm-picker__badge--default';
    }

    _recordTypeLabel(recordType) {
        return recordType === 'Repasse__c' ? 'Repasse' : 'Oportunidade';
    }

    _recordTypeClass(recordType) {
        return recordType === 'Repasse__c'
            ? 'comm-picker__badge comm-picker__badge--purple'
            : 'comm-picker__badge comm-picker__badge--orange';
    }

    _effectiveRecordType(recordType, hasRepasse) {
        return hasRepasse || recordType === 'Repasse__c'
            ? 'Repasse__c'
            : 'Opportunity';
    }

    _recentSortRecordId(threadInfo) {
        if (!threadInfo) {
            return null;
        }
        return this._effectiveRecordType(threadInfo.recordType, threadInfo.hasRepasse) === 'Repasse__c'
            ? (threadInfo.repasseOpportunityId || threadInfo.recordId || null)
            : (threadInfo.recordId || null);
    }

    _buildTypeBadgeData(recordType, hasRepasse) {
        const effectiveType = this._effectiveRecordType(recordType, hasRepasse);
        return {
            label: this._recordTypeLabel(effectiveType),
            className: this._recordTypeClass(effectiveType)
        };
    }

    _buildDisplayStatusData(recordInfo, relatedRefs = null) {
        const effectiveType = this._effectiveRecordType(recordInfo?.recordType, recordInfo?.hasRepasse);
        const isRepasse = effectiveType === 'Repasse__c';
        const isOpportunityNegotiation = !isRepasse && this._getOpportunityFilterValue(recordInfo || {}) === 'opportunity_negociacao';
        const hasQuoteCount = relatedRefs?.quoteCount !== undefined && relatedRefs?.quoteCount !== null;
        if (isOpportunityNegotiation && hasQuoteCount) {
            const quoteCount = Number(relatedRefs?.quoteCount || 0);
            const quoteStatus = this._buildQuoteCountStatus(quoteCount);
            return {
                value: quoteStatus,
                label: recordInfo?.displayStatusLabel || 'Fase atual:',
                className: this._stageClass(quoteStatus)
            };
        }

        const rawValue = isRepasse
            ? (recordInfo?.displayStatus || recordInfo?.currentStage || recordInfo?.rawRepasseStatus || '')
            : (recordInfo?.displayStatus || recordInfo?.currentStage || recordInfo?.stageName || '');
        const label = isRepasse
            ? 'Fase atual:'
            : (recordInfo?.displayStatusLabel || 'Fase atual:');
        const value = this._formatStatusLabel(rawValue);

        return {
            value,
            label,
            className: this._stageClass(value)
        };
    }

    _formatStatusLabel(value) {
        if (!value) return '';
        const tokenMap = { ir: 'IR', pj: 'PJ', sfh: 'SFH' };
        const normalizedWords = this._normalizeStatusKey(value).split(' ').filter(Boolean);
        const displayWords = String(value).toLowerCase().normalize('NFC').trim().replace(/\s+/g, ' ').split(' ').filter(Boolean);
        return normalizedWords.map((normalizedWord, index) => {
            const mapped = tokenMap[normalizedWord];
            if (mapped) return mapped;
            const displayWord = displayWords[index] || '';
            return displayWord ? displayWord.charAt(0).toUpperCase() + displayWord.slice(1) : '';
        }).filter(Boolean).join(' ');
    }

    _normalizeStatusKey(value) {
        return String(value || '')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' ');
    }

    _collectThreadIdsForPresenceOverride() {
        return [...new Set(
            (this._rawThreads || [])
                .map(threadInfo => this._normalizePresenceThreadId(threadInfo?.threadId))
                .filter(Boolean)
        )];
    }

    async _refreshThreadPresenceOverrides() {
        const threadIds = this._collectThreadIdsForPresenceOverride();
        if (threadIds.length === 0) {
            this.threadPresenceOverrideByThreadId = {};
            return;
        }
        try {
            const overrides = await getThreadPresenceOverrides({ threadIds });
            this.threadPresenceOverrideByThreadId = this._buildThreadPresenceOverridesMap(overrides);
        } catch (error) {
            this.threadPresenceOverrideByThreadId = {};
        }
    }

    _buildThreadPresenceOverridesMap(overrides) {
        const mapByThreadId = {};
        (overrides || []).forEach(override => {
            const threadId = this._normalizePresenceThreadId(override?.threadId);
            const rawUserId = String(override?.userId || '').trim();
            const userId18 = this._normalizePresenceUserId18(rawUserId);
            const userId15 = this._normalizePresenceUserId(rawUserId);
            const userId = userId18 || userId15;
            const status = String(override?.status || '').toLowerCase();
            if (!threadId || !userId) return;
            if (status !== 'online' && status !== 'offline') return;
            mapByThreadId[threadId] = {
                userId,
                rawUserId: rawUserId || userId,
                status
            };
        });
        return mapByThreadId;
    }

    _normalizePresenceThreadId(value) {
        const rawValue = String(value || '').trim();
        return rawValue ? rawValue.toUpperCase() : '';
    }

    _resolveThreadPresenceContext(threadInfo) {
        const threadId = this._normalizePresenceThreadId(threadInfo?.threadId);
        const override = this.threadPresenceOverrideByThreadId?.[threadId];
        if (override?.userId) {
            return {
                userId: override.userId,
                rawUserId: override.rawUserId || override.userId,
                statusOverride: override.status || null
            };
        }
        const rawUserId = String(threadInfo?.lastSenderId || '').trim();
        const caseSensitive18 = this._normalizePresenceUserId18(rawUserId);
        return {
            userId: caseSensitive18 || this._normalizePresenceUserId(rawUserId),
            rawUserId,
            statusOverride: null
        };
    }

    _collectThreadPresenceUserIds() {
        const queryUserIds = [];
        (this._rawThreads || []).forEach(threadInfo => {
            const context = this._resolveThreadPresenceContext(threadInfo);
            queryUserIds.push(...this._buildPresenceUserIdCandidates(context?.rawUserId || context?.userId));
        });
        return [...new Set(queryUserIds.filter(Boolean))];
    }

    _collectOpenChatThreadIds() {
        const threadIds = this.chatThreadIds.length > 0
            ? this.chatThreadIds
            : (this.threadId ? [this.threadId] : []);
        return [...new Set(
            threadIds
                .map(threadId => this._normalizePresenceThreadId(threadId))
                .filter(Boolean)
        )];
    }

    async _collectOpenChatPresenceUserIds() {
        const threadIds = this._collectOpenChatThreadIds();
        if (threadIds.length === 0) return [];
        const participantIds = await getThreadHistoryParticipantIdsAcrossThreads({ threadIds });
        const currentUserId18 = this._normalizePresenceUserId18(USER_ID);
        const currentUserId15 = this._normalizePresenceUserId(USER_ID);
        const queryUserIds = [...new Set(
            (participantIds || [])
                .flatMap(userId => this._buildPresenceUserIdCandidates(userId))
                .filter(Boolean)
        )];
        return queryUserIds.filter(userId => {
            const candidate18 = this._normalizePresenceUserId18(userId);
            if (candidate18 && currentUserId18) return candidate18 !== currentUserId18;
            return this._normalizePresenceUserId(userId) !== currentUserId15;
        });
    }

    async _validatePresenceIdsOnChatOpen() {
        if (!this.showChat || !isSocketConnected()) return;
        const peerUserIds = await this._collectOpenChatPresenceUserIds();
        const queryUserIds = [...new Set([
            ...peerUserIds,
            ...this._buildPresenceUserIdCandidates(USER_ID)
        ].filter(Boolean))];
        if (queryUserIds.length === 0) return;
        const response = await getUsersConnectionStatus(queryUserIds);
        const parsedMap = this._buildThreadPresenceMap(response);
        const currentUserKey15 = this._normalizePresenceUserId(USER_ID);
        const currentUserKey18 = this._normalizePresenceUserId18(USER_ID);
        if (currentUserKey15) delete parsedMap[currentUserKey15];
        if (currentUserKey18) delete parsedMap[currentUserKey18];
        if (Object.keys(parsedMap).length > 0) {
            this.threadPresenceStatusByUserId = {
                ...this.threadPresenceStatusByUserId,
                ...parsedMap
            };
        }
        this._syncPresencePollingByStatus();
    }

    async _refreshThreadPresenceStatuses() {
        if (!isSocketConnected()) return;
        const userIds = this._collectThreadPresenceUserIds();
        if (userIds.length === 0) {
            this.threadPresenceStatusByUserId = {};
            this._syncPresencePollingByStatus();
            return;
        }
        try {
            const response = await getUsersConnectionStatus(userIds);
            const parsedMap = this._buildThreadPresenceMap(response);
            if (Object.keys(parsedMap).length > 0) {
                this.threadPresenceStatusByUserId = parsedMap;
            }
            this._syncPresencePollingByStatus();
        } catch (error) {
            // Keep previous presence state when socket lookup fails.
            this._syncPresencePollingByStatus();
        }
    }

    _syncPresencePollingByStatus() {
        if (this._hasAnyOnlinePresence()) {
            this._startPresenceOnlinePolling();
            return;
        }
        this._stopPresenceOnlinePolling();
    }

    _hasAnyOnlinePresence() {
        return this._hasAnyOnlineSocketPresence() || this._hasAnyOnlineOverridePresence();
    }

    _hasAnyOnlineSocketPresence() {
        return Object.values(this.threadPresenceStatusByUserId || {})
            .some(status => status === 'online');
    }

    _hasAnyOnlineOverridePresence() {
        return Object.values(this.threadPresenceOverrideByThreadId || {})
            .some(override => String(override?.status || '').toLowerCase() === 'online');
    }

    _startPresenceOnlinePolling() {
        if (this._presenceOnlinePollTimer) return;
        this._presenceOnlinePollTimer = setInterval(() => {
            this._queueThreadPresenceRefresh();
        }, ONLINE_PRESENCE_REFRESH_MS);
    }

    _stopPresenceOnlinePolling() {
        if (!this._presenceOnlinePollTimer) return;
        clearInterval(this._presenceOnlinePollTimer);
        this._presenceOnlinePollTimer = null;
    }

    _queueThreadPresenceRefresh() {
        const runRefresh = () => {
            Promise.resolve()
                .then(() => this._refreshThreadPresenceOverrides())
                .catch(() => {})
                .finally(() => this._refreshThreadPresenceStatuses().catch(() => {}));
        };
        if (typeof window !== 'undefined' && typeof window.requestAnimationFrame === 'function') {
            window.requestAnimationFrame(runRefresh);
            return;
        }
        setTimeout(runRefresh, 0);
    }

    _buildPresenceUserIdCandidates(value) {
        const rawUserId = String(value || '').trim();
        const caseSensitive18 = this._normalizePresenceUserId18(rawUserId);
        const normalizedUserId = this._normalizePresenceUserId(rawUserId);
        const candidates = caseSensitive18
            ? [caseSensitive18]
            : [rawUserId, normalizedUserId].filter(Boolean);
        return [...new Set(candidates)];
    }

    _buildThreadPresenceMap(response) {
        const presenceMap = {};
        const entries = this._extractPresenceEntries(response);
        entries.forEach(entry => {
            const key = this._resolvePresenceUserKey(entry);
            if (!key) return;
            const status = this._resolvePresenceConnectionState(entry, true) ? 'online' : 'offline';
            presenceMap[key] = status;
            const rawUserId = String(entry?.userId || entry?.user_id || entry?.id || entry?.Id || '').trim();
            const key18 = this._normalizePresenceUserId18(rawUserId);
            const key15 = this._normalizePresenceUserId(rawUserId);
            if (key18) presenceMap[key18] = status;
            if (key15) presenceMap[key15] = status;
        });
        return presenceMap;
    }

    _extractPresenceEntries(response) {
        if (!response) return [];
        if (Array.isArray(response)) {
            return response.map(item => {
                if (item && typeof item === 'object') return item;
                if (typeof item === 'string' || typeof item === 'number') {
                    return { userId: String(item), status: 'online' };
                }
                return null;
            }).filter(Boolean);
        }
        if (typeof response !== 'object') return [];

        const directArrays = [
            response.users,
            response.onlineUsers,
            response.participants,
            response.connections,
            response.statuses,
            response?.data?.users,
            response?.payload?.users,
            response?.result?.users
        ].filter(Array.isArray);
        if (directArrays.length > 0) {
            return directArrays
                .flat()
                .map(item => {
                    if (item && typeof item === 'object') return item;
                    if (typeof item === 'string' || typeof item === 'number') {
                        return { userId: String(item), status: 'online' };
                    }
                    return null;
                })
                .filter(Boolean);
        }

        const entries = [];
        Object.entries(response).forEach(([key, value]) => {
            if (Array.isArray(value)) {
                if (this._isSalesforceUserId(key)) {
                    if (value.length === 0) {
                        entries.push({ userId: key, connections: 0 });
                        return;
                    }
                    value.forEach(item => {
                        if (item && typeof item === 'object') {
                            if (this._resolvePresenceUserKey(item)) {
                                entries.push(item);
                                return;
                            }
                            entries.push({ ...item, userId: key, connections: value.length });
                            return;
                        }
                        entries.push({
                            userId: key,
                            socketId: String(item || ''),
                            connections: value.length,
                            status: 'online'
                        });
                    });
                    return;
                }
                value.forEach(item => {
                    if (item && typeof item === 'object') entries.push(item);
                });
                return;
            }
            if (value && typeof value === 'object') {
                if (this._resolvePresenceUserKey(value)) entries.push(value);
                else if (this._isSalesforceUserId(key)) entries.push({ ...value, userId: key });
                return;
            }
            if (this._isSalesforceUserId(key)) entries.push({ userId: key, status: value });
        });
        return entries;
    }

    _resolvePresenceUserKey(entry) {
        if (!entry) return '';
        const candidates = [
            entry.userId,
            entry.user_id,
            entry.id,
            entry.Id,
            entry.user,
            entry.sfUserId,
            entry.sf_user_id,
            entry.salesforceId,
            entry.salesforce_id,
            entry.participantId,
            entry.participant_id,
            entry.contactId,
            entry.contact_id,
            entry.username,
            entry.login
        ];
        for (const candidateId of candidates) {
            const caseSensitive18 = this._normalizePresenceUserId18(candidateId);
            if (caseSensitive18) return caseSensitive18;
        }
        for (const candidateId of candidates) {
            const normalizedUserId = this._normalizePresenceUserId(candidateId);
            if (normalizedUserId) return normalizedUserId;
        }
        return '';
    }

    _resolvePresenceConnectionState(value, assumeOnlineWhenNoSignal = false) {
        if (typeof value === 'boolean') return value;
        if (typeof value === 'number') return value > 0;
        if (typeof value === 'string') return this._isOnlinePresenceKeyword(value);
        if (!value || typeof value !== 'object') return false;
        if (typeof value.connections === 'number') return value.connections > 0;
        if (typeof value.connectionCount === 'number') return value.connectionCount > 0;
        if (typeof value.connected === 'boolean') return value.connected;
        if (typeof value.isOnline === 'boolean') return value.isOnline;
        if (typeof value.online === 'boolean') return value.online;
        if (this._isOnlinePresenceKeyword(value.status)) return true;
        if (this._isOnlinePresenceKeyword(value.connectionStatus)) return true;
        if (this._isOnlinePresenceKeyword(value.state)) return true;
        if (this._isOnlinePresenceKeyword(value.socketStatus)) return true;
        if (value.socketId || value.socket_id || value.sid) return true;
        if (assumeOnlineWhenNoSignal && !this._hasPresenceSignal(value)) return true;
        return false;
    }

    _hasPresenceSignal(value) {
        if (!value || typeof value !== 'object') return false;
        return (typeof value.connected === 'boolean')
            || (typeof value.isOnline === 'boolean')
            || (typeof value.online === 'boolean')
            || (typeof value.connections === 'number')
            || (typeof value.connectionCount === 'number')
            || (typeof value.status === 'string')
            || (typeof value.connectionStatus === 'string')
            || (typeof value.state === 'string')
            || (typeof value.socketStatus === 'string');
    }

    _isOnlinePresenceKeyword(value) {
        const normalizedValue = String(value || '').toLowerCase();
        return ['online', 'connected', 'active', 'available', 'true', '1'].includes(normalizedValue);
    }

    _normalizePresenceUserId(value) {
        const rawValue = String(value || '').trim();
        return rawValue ? rawValue.substring(0, 15).toUpperCase() : '';
    }

    _normalizePresenceUserId18(value) {
        const rawValue = String(value || '').trim();
        return rawValue.length === 18 ? rawValue : '';
    }

    _resolveThreadPresenceStatus(userId, statusOverride = null, rawUserId = null) {
        if (statusOverride === 'online' || statusOverride === 'offline') {
            return statusOverride;
        }
        const idSource = rawUserId || userId;
        const normalizedUserId = this._normalizePresenceUserId(idSource);
        const normalizedUserId18 = this._normalizePresenceUserId18(idSource);
        if (!normalizedUserId && !normalizedUserId18) return 'offline';
        return this.threadPresenceStatusByUserId?.[normalizedUserId18]
            || this.threadPresenceStatusByUserId?.[normalizedUserId]
            || 'offline';
    }

    _setThreadPresenceOffline() {
        const nextPresenceMap = {};
        Object.keys(this.threadPresenceStatusByUserId || {}).forEach(userId => {
            nextPresenceMap[userId] = 'offline';
        });
        this.threadPresenceStatusByUserId = nextPresenceMap;
    }

    _queueLiveNotificationFromSocketMessage(msg) {
        if (!this._isSocketMessageForCurrentUser(msg)) return;
        if (this._isSocketMessageFromCurrentUser(msg)) return;
        const sequenceNumber = ++this._liveNotificationSequence;
        setTimeout(() => {
            this._processLiveNotificationFromSocketMessage(msg, sequenceNumber).catch(() => {});
        }, 0);
    }

    async _processLiveNotificationFromSocketMessage(msg, sequenceNumber) {
        const targetThreadInfo = await this._resolveLiveThreadTargetFromSocketMessage(msg);
        if (sequenceNumber !== this._liveNotificationSequence) return;
        this._registerLiveNotification(targetThreadInfo);
    }

    _isSocketMessageForCurrentUser(msg) {
        const recipientIds = this._normalizeSocketUserIds(msg);
        if (recipientIds.length === 0) return true;
        const currentUserId = this._normalizePresenceUserId(USER_ID);
        if (!currentUserId) return true;
        const salesforceRecipientIds = recipientIds
            .map(recipientId => this._normalizePresenceUserId(recipientId))
            .filter(recipientId => this._isSalesforceUserId(recipientId));
        if (salesforceRecipientIds.length === 0) return true;
        return salesforceRecipientIds.includes(currentUserId);
    }

    _isSocketMessageFromCurrentUser(msg) {
        const senderId = String(msg?.senderId || msg?.sender_id || '').trim();
        const currentUserId = String(USER_ID || '').trim();
        if (!senderId || !currentUserId) return false;
        return senderId.substring(0, 15).toUpperCase() === currentUserId.substring(0, 15).toUpperCase();
    }

    async _resolveLiveThreadTargetFromSocketMessage(msg) {
        const threadIds = this._extractSocketThreadIds(msg);
        let threadCard = this._findThreadCardByThreadIds(threadIds);
        let targetThreadInfo = this._buildLiveTargetFromThreadCard(threadCard);
        if (targetThreadInfo?.recordId) return targetThreadInfo;
        await this._refreshLiveNotificationThreadSnapshot();
        threadCard = this._findThreadCardByThreadIds(threadIds);
        targetThreadInfo = this._buildLiveTargetFromThreadCard(threadCard);
        if (targetThreadInfo?.recordId) return targetThreadInfo;
        targetThreadInfo = this._resolveCurrentChatThreadTarget(threadIds);
        if (targetThreadInfo?.recordId) return targetThreadInfo;
        return this._resolveLatestUnreadThreadTarget();
    }

    _extractSocketThreadIds(msg) {
        const threadIdValues = Array.isArray(msg?.threadIds)
            ? msg.threadIds
            : [msg?.threadIds];
        return [...new Set([
            msg?.threadId,
            msg?.thread_id,
            msg?.threadExternalId,
            msg?.thread_external_id,
            ...threadIdValues
        ].map(value => String(value || '').trim()).filter(Boolean))];
    }

    async _refreshLiveNotificationThreadSnapshot() {
        if (this._liveSnapshotPromise) return this._liveSnapshotPromise;
        this._liveSnapshotPromise = (async () => {
            try {
                const snapshot = await getOpportunityChatList({ pageSize: THREAD_PAGE_SIZE, offsetVal: 0, filter: 'all', keyword: '' });
                if (!Array.isArray(snapshot)) return;
                this._rawThreads = snapshot;
                this._applyFilter();
            } catch (error) {
                // Ignore snapshot failures to keep live reception resilient.
            } finally {
                this._liveSnapshotPromise = null;
            }
        })();
        return this._liveSnapshotPromise;
    }

    _findThreadCardByThreadIds(threadIds) {
        if (!Array.isArray(threadIds) || threadIds.length === 0) return null;
        const threadIdSet = new Set(
            threadIds.map(threadId => String(threadId || '').trim().toUpperCase()).filter(Boolean)
        );
        const threadCards = Array.isArray(this._rawThreads) ? this._rawThreads : [];
        return threadCards.find(threadCard => threadIdSet.has(String(threadCard?.threadId || '').trim().toUpperCase())) || null;
    }

    _buildLiveTargetFromThreadCard(threadCard) {
        if (!threadCard) return null;
        const recordId = String(threadCard.recordId || '').trim();
        if (!recordId) return null;
        const objectType = this._effectiveRecordType(threadCard.recordType, threadCard.hasRepasse);
        return {
            threadId: String(threadCard.threadId || '').trim() || null,
            recordId,
            recordName: threadCard.recordName || 'Oportunidade',
            objectType
        };
    }

    _resolveLatestUnreadThreadTarget() {
        const unreadThreads = (this._rawThreads || [])
            .filter(threadCard => Number(threadCard?.unreadCount || 0) > 0);
        if (unreadThreads.length === 0) return null;
        unreadThreads.sort((leftThread, rightThread) =>
            this._parseListDateTime(rightThread?.lastMessageAt) - this._parseListDateTime(leftThread?.lastMessageAt)
        );
        return this._buildLiveTargetFromThreadCard(unreadThreads[0]);
    }

    _resolveCurrentChatThreadTarget(threadIds) {
        if (!this.showChat || !this.opportunityId) return null;
        const currentThreadId = String(this.threadId || '').trim().toUpperCase();
        const normalizedThreadIds = (threadIds || [])
            .map(threadId => String(threadId || '').trim().toUpperCase())
            .filter(Boolean);
        if (normalizedThreadIds.length > 0 && !normalizedThreadIds.includes(currentThreadId)) {
            return null;
        }
        return {
            threadId: this.threadId || null,
            recordId: this.opportunityId,
            recordName: this.opportunityName || 'Oportunidade',
            objectType: this.activeRecordTypeLabel === 'Repasse' ? 'Repasse__c' : 'Opportunity'
        };
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

    _registerLiveNotification(targetThreadInfo) {
        const resolvedTargetThreadInfo = targetThreadInfo || {};
        this.liveNotificationCount += 1;
        if (!resolvedTargetThreadInfo.recordId && !resolvedTargetThreadInfo.threadId) return;
        this.liveNotificationTargetThreadId = resolvedTargetThreadInfo.threadId || null;
        this.liveNotificationTargetRecordId = resolvedTargetThreadInfo.recordId || null;
        this.liveNotificationTargetRecordName = resolvedTargetThreadInfo.recordName || 'Oportunidade';
        this.liveNotificationTargetObjectType = resolvedTargetThreadInfo.objectType || 'Opportunity';
    }

    _clearLiveNotificationIfMatchingOpenChat(threadId, recordId) {
        if (this.liveNotificationCount <= 0) return;
        const normalizedThreadId = String(threadId || '').trim().toUpperCase();
        const normalizedTargetThreadId = String(this.liveNotificationTargetThreadId || '').trim().toUpperCase();
        if (normalizedThreadId && normalizedTargetThreadId && normalizedThreadId === normalizedTargetThreadId) {
            this._clearLiveNotificationBadge();
            return;
        }
        if (recordId && this.liveNotificationTargetRecordId === recordId) {
            this._clearLiveNotificationBadge();
        }
    }

    _clearLiveNotificationBadge() {
        this.liveNotificationCount = 0;
        this.liveNotificationTargetThreadId = null;
        this.liveNotificationTargetRecordId = null;
        this.liveNotificationTargetRecordName = '';
        this.liveNotificationTargetObjectType = 'Opportunity';
    }

    _resetCompactChatterHistory() {
        this.showChatterHistory = false;
        this._resetCompactChatterSearchState();
    }

    _resetCompactChatterSearchState() {
        this.chatterSearchTerm = '';
        this.chatterSearchResults = [];
        this.isChatterSearchLoading = false;
        this.isChatterSearchComplete = false;
    }

    _isSalesforceUserId(value) {
        return /^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$/.test(String(value || '').trim());
    }

    _resolveThreadDisplayName(thread) {
        const isRepasse = this._effectiveRecordType(thread.recordType, thread.hasRepasse) === 'Repasse__c';
        if (this._isSalesforcePlatformUser && isRepasse) {
            return thread.repasseName || thread.recordName;
        }
        return thread.recordName;
    }

    _resolveRecentDisplayName(opp) {
        if (!this._isSalesforcePlatformUser) return opp.name;
        const thread = this._rawThreads.find(t => t.recordId === opp.id && t.hasRepasse);
        return thread?.recordName || opp.name;
    }

    _unreadText(unreadCount) {
        const n = unreadCount > 99 ? '99+' : String(unreadCount);
        return unreadCount === 1 ? `${n} mensagem` : `${n} mensagens`;
    }

    async _loadHistory(recordId) {
        this.isLoadingHistory = true;
        try {
            const url = `/services/apexrest/communicator/history/?recordId=${recordId}`;
            const response = await fetch(url, {
                method: 'GET',
                headers: { 'Content-Type': 'application/json' }
            });
            const data = JSON.parse(await response.text());
            this.historyMessages = data.success ? data.messages : [];
        } catch (e) {
            console.error('_loadHistory:', e);
            this.historyMessages = [];
        } finally {
            this.isLoadingHistory = false;
        }
    }

    // ─────────────────────────────────────────
    // Socket
    // ─────────────────────────────────────────

    get statusDotClass() {
        return `status-dot status-${this.socketStatus}`;
    }

    get statusTooltip() {
        const map = { online: 'Online', offline: 'Offline', connecting: 'Conectando...' };
        return map[this.socketStatus] || 'Offline';
    }

    _socketStatusLabel(status) {
        const map = { online: 'Online', offline: 'Offline', connecting: 'Conectando...' };
        return map[status] || 'Offline';
    }

    async initSocket() {
        if (this._socketAcquired) return;
        this.socketStatus = 'connecting';
        const origin = window.location.pathname.startsWith('/s/') ? 'experience' : 'lex';
        try {
            await connectSocket(this, { origin });
            this._socketAcquired = true;
            acquireSocket();
            this.socketStatus = 'online';
            this._queueThreadPresenceRefresh();
            this._socketUnsubscribes.push(
                onSocket('connect', () => {
                    this.socketStatus = 'online';
                    this._queueThreadPresenceRefresh();
                }),
                onSocket('disconnect', () => {
                    this.socketStatus = 'offline';
                    this._setThreadPresenceOffline();
                    this._stopPresenceOnlinePolling();
                }),
                onSocket('receivedMessage', (msg) => this.handleIncomingSocketMessage(msg))
            );
        } catch (err) {
            this.socketStatus = 'offline';
            console.error('[Comunicador] Falha ao conectar socket', err);
        }
    }

    teardownSocket() {
        this._socketUnsubscribes.forEach((fn) => fn());
        this._socketUnsubscribes = [];
        if (this._socketAcquired) {
            releaseSocket();
            this._socketAcquired = false;
        }
        this.socketStatus = 'offline';
        this._setThreadPresenceOffline();
        this._stopPresenceOnlinePolling();
    }

    handleIncomingSocketMessage(msg) {
        console.log('[Comunicador] Mensagem recebida via socket', msg);
        const socketMessageId = this._extractSocketMessageId(msg);
        this.historyMessages = [...(this.historyMessages || []), {
            id: socketMessageId,
            message: msg.message,
            direction: 'in',
            timestamp: new Date().toISOString()
        }];
        this._refreshGlobalUnreadCount().catch(() => {});
        this._queueLiveNotificationFromSocketMessage(msg);
        this._reconcileIncomingSocketMessage(msg, socketMessageId);
    }

    _extractSocketMessageId(msg) {
        return msg?.messageId || msg?.message_id || null;
    }

    _normalizeSocketUserIds(msg) {
        const rawValues = [
            msg?.user_ids,
            msg?.userIds,
            msg?.recipientIds,
            msg?.recipients,
            msg?.users
        ];
        const ids = rawValues.flatMap(rawValue => this._extractSocketUserIds(rawValue));
        return [...new Set(ids.map(id => String(id || '').trim()).filter(Boolean))];
    }

    _extractSocketUserIds(rawValue) {
        if (!rawValue) return [];
        if (Array.isArray(rawValue)) return rawValue.filter(Boolean);
        if (typeof rawValue === 'string') {
            const textValue = rawValue.trim();
            if (!textValue) return [];
            if (textValue.startsWith('[') && textValue.endsWith(']')) {
                try {
                    const parsedValue = JSON.parse(textValue);
                    return this._extractSocketUserIds(parsedValue);
                } catch (error) {
                    // Fall back to token split.
                }
            }
            return textValue.split(/[,\s;]+/).filter(Boolean);
        }
        if (typeof rawValue === 'object') {
            return [
                rawValue.userId,
                rawValue.user_id,
                rawValue.id
            ].filter(Boolean);
        }
        return [];
    }

    _reconcileIncomingSocketMessage(msg, socketMessageId) {
        if (!socketMessageId) return;
        const userIds = this._normalizeSocketUserIds(msg);
        reconcileSocketMessage({
            threadId: this.threadId || null,
            threadExternalId: msg?.threadExternalId || msg?.thread_external_id || null,
            messageId: socketMessageId,
            messageBody: msg?.message || null,
            userIdsJson: JSON.stringify(userIds),
            senderExternalId: msg?.senderId || msg?.sender_id || null
        }).catch((error) => {
            // The local near-real-time UX must never break on backend reconciliation failures.
            console.error('[Comunicador] Falha ao reconciliar mensagem recebida via socket', error);
        });
    }
}