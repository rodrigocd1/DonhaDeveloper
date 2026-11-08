import { LightningElement, api, track } from 'lwc';
import CommunicatorChatHistoryModal from 'c/communicatorChatHistoryModal';
import { isSalesforceMobileApp, buildDisabledFeatureToast, SALESFORCE_APP_DISABLED_MESSAGE } from 'c/communicatorEnvironment';
import getThreadsForRecord from '@salesforce/apex/CommunicatorChatController.getThreadsForRecord';
import getSettings from '@salesforce/apex/CommunicatorChatController.getSettings';
import getOpportunityIdForAnaliseFinanceira from '@salesforce/apex/CommunicatorChatController.getOpportunityIdForAnaliseFinanceira';
import SYSTEM_AVATAR from '@salesforce/resourceUrl/communicatorSystemAvatar';

const DEFAULT_AVATAR = '/img/icon/t4v35/standard/person_account_120.png';

const DEFAULT_POLL_MS = 6000;
const MIN_POLL_MS = 3000;
const STAGE_ORDER = [
    'Montagem de pasta',
    'Apuração de renda',
    'Análise de crédito',
    'Negociação',
    'Condição crédito',
    'Condição comercial',
    'Contrato',
    'Oportunidade ganha'
];

export default class CommunicatorUnreadAlert extends LightningElement {

    @api objectApiName;
    @api inlineMode = false;

    @track _threads    = [];
    @track _allThreads = [];
    _recordId       = null;
    _opportunityId  = null;
    _pollTimer      = null;
    _pollIntervalMs = DEFAULT_POLL_MS;
    _connectedCallbackDone = false;
    _initToken      = 0;

    @api
    get recordId() { return this._recordId; }
    set recordId(val) {
        const prev = this._recordId;
        this._recordId = val;
        if (val && val !== prev && this._connectedCallbackDone) {
            this._reinitialize();
        }
    }

    async connectedCallback() {
        await this._resolveOpportunityId();
        await this._loadConfig();
        await this._poll();
        this._startPolling();
        this._connectedCallbackDone = true;
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    async _reinitialize() {
        const token = ++this._initToken;
        this._stopPolling();
        this._opportunityId = null;
        this._allThreads    = [];
        this._threads       = [];
        await this._resolveOpportunityId();
        if (token !== this._initToken) return;
        await this._loadConfig();
        if (token !== this._initToken) return;
        await this._poll();
        if (token !== this._initToken) return;
        this._startPolling();
    }

    async _resolveOpportunityId() {
        if (!this.recordId) return;
        if (this.objectApiName === 'Opportunity' || String(this.recordId).startsWith('006')) {
            this._opportunityId = this.recordId;
            return;
        }
        try {
            this._opportunityId = await getOpportunityIdForAnaliseFinanceira({ afId: this.recordId });
        } catch (e) {
            this._opportunityId = null;
        }
    }

    async _loadConfig() {
        try {
            const s = await getSettings();
            if (s && s.pollingIntervalMs >= MIN_POLL_MS) {
                this._pollIntervalMs = s.pollingIntervalMs;
            }
        } catch (e) { /* keep default */ }
    }

    async _poll() {
        if (!this._opportunityId) return;
        try {
            const threads = await getThreadsForRecord({ recordId: this._opportunityId });
            this._allThreads = threads || [];
            this._threads    = this._allThreads.filter(t => (t.unreadCount || 0) > 0);
        } catch (e) { /* keep last state */ }
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

    get isModalActionDisabled() {
        return !this.inlineMode && isSalesforceMobileApp();
    }

    get modalActionAriaDisabled() {
        return this.isModalActionDisabled ? 'true' : null;
    }

    get modalActionTitle() {
        return this.isModalActionDisabled ? SALESFORCE_APP_DISABLED_MESSAGE : null;
    }

    get threadLinkClass() {
        return this.isModalActionDisabled
            ? 'comm-unread-alert__thread-link comm-is-disabled'
            : 'comm-unread-alert__thread-link';
    }

    get lastLabelClass() {
        return this.isModalActionDisabled
            ? 'comm-unread-alert__last-label comm-is-disabled'
            : 'comm-unread-alert__last-label';
    }

    handleThreadClick(event) {
        const threadId = event.currentTarget.dataset.threadId;
        if (this.inlineMode) {
            this.dispatchEvent(new CustomEvent('threadclick', { detail: { threadId } }));
            return;
        }
        if (this.isModalActionDisabled) {
            this.dispatchEvent(buildDisabledFeatureToast());
            return;
        }
        if (!this._opportunityId) return;
        CommunicatorChatHistoryModal.open({
            size: 'large',
            recordId: this._opportunityId,
            initialThreadId: threadId
        }).catch(console.error);
    }

    _toCanonicalOppStage(stageName) {
        const s = (stageName || '')
            .normalize('NFD')
            .replace(/[̀-ͯ]/g, '')
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' ');
        if (s.includes('montagem'))                                                          return 'Montagem de pasta';
        if (s.includes('apuracao de renda') || s.includes('analise de renda'))              return 'Apuração de renda';
        if (s.includes('analise de credito') || s.includes('cotacao') ||
            s.includes('cotacoes') || s.includes('aprovacao bancaria'))                     return 'Análise de crédito';
        if (s.includes('negoci'))                                                            return 'Negociação';
        if (s.includes('condicao credito') || s.includes('aprovacao da condicao'))          return 'Condição crédito';
        if (s.includes('condicao comercial') || (s.includes('comercial') && !s.includes('credito'))) return 'Condição comercial';
        if (s.includes('contrato') && !s.includes('assinado') && !s.includes('ganha'))      return 'Contrato';
        if (s.includes('assinado') || s.includes('ganha') || s.includes('desembolsado'))    return 'Oportunidade ganha';
        return stageName || '';
    }

    get hasUnread() {
        return this._threads.length > 0;
    }

    get lastReadMessage() {
        if (this.hasUnread || this._allThreads.length === 0) return null;
        const recent = [...this._allThreads].reverse().find(t => t.lastMessageBody);
        if (!recent) return null;
        const body = recent.lastMessageBody || '';
        const truncated = body.length > 120 ? body.substring(0, 120) + '...' : body;
        const isSystem = recent.lastIsSystemMessage;
        return {
            threadId:    recent.threadId,
            senderName:  isSystem ? 'Sistema' : (recent.lastSenderName || ''),
            senderPhoto: isSystem ? (SYSTEM_AVATAR || DEFAULT_AVATAR) : (recent.lastSenderPhoto || DEFAULT_AVATAR),
            preview:     truncated,
            time:        recent.lastMessageAt || ''
        };
    }

    handleLastMessageClick() {
        const msg = this.lastReadMessage;
        if (!msg) return;
        if (this.inlineMode) {
            this.dispatchEvent(new CustomEvent('lastmessageclick', { detail: { threadId: msg.threadId } }));
            return;
        }
        if (this.isModalActionDisabled) {
            this.dispatchEvent(buildDisabledFeatureToast());
            return;
        }
        if (!this._opportunityId) return;
        CommunicatorChatHistoryModal.open({
            size: 'large',
            recordId:        this._opportunityId,
            initialThreadId: msg.threadId
        }).catch(console.error);
    }

    handleAvatarError(event) {
        const img = event && event.target;
        if (!img || img.dataset.fallbackApplied === 'true') return;
        img.dataset.fallbackApplied = 'true';
        img.src = '/img/icon/t4v35/standard/person_account_120.png';
    }

    get showEmpty() {
        return !this.hasUnread && !this.lastReadMessage;
    }

    get threadItems() {
        return this._threads
            .map(t => {
                const count = t.unreadCount || 0;
                return {
                    key:        t.threadId,
                    threadId:   t.threadId,
                    label:      this._toCanonicalOppStage(t.stageName),
                    badgeLabel: count > 99 ? '99+' : String(count)
                };
            })
            .sort((a, b) => {
                const ai = STAGE_ORDER.indexOf(a.label);
                const bi = STAGE_ORDER.indexOf(b.label);
                return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
            });
    }
}