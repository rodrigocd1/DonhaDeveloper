import { LightningElement, api, track, wire } from 'lwc';
import getOrCreateThread from '@salesforce/apex/CommunicatorChatController.getOrCreateThread';
import getUnreadCount    from '@salesforce/apex/CommunicatorChatController.getUnreadCount';
import markThreadAsRead  from '@salesforce/apex/CommunicatorChatController.markThreadAsRead';
import getSettings       from '@salesforce/apex/CommunicatorChatController.getSettings';

const DEFAULT_POLL_MS = 6000;
const MODE_FAB         = 'fab';
const MODE_UTILITY     = 'utility';

export default class CommunicatorChat extends LightningElement {

    /**
     * Define o modo de renderização:
     * - "fab"     → botão flutuante (Experience Cloud)
     * - "utility" → painel da utility bar (Lightning Experience)
     * Padrão: "fab"
     */
    @api mode = MODE_FAB;



    @track isOpen          = false;
    @track _settings       = null;

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) this._settings = data;
    }
    @track showChat        = false;
    @track threadId        = null;
    @track opportunityName = '';
    @track unreadCount     = 0;

    _pollTimer = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    disconnectedCallback() {
        this._stopPolling();
    }

    // ─────────────────────────────────────────
    // FAB handlers
    // ─────────────────────────────────────────

    handleFabToggle() {
        this.isOpen = !this.isOpen;
    }

    handleFabClose() {
        this.isOpen = false;
    }

    // ─────────────────────────────────────────
    // Opportunity selecionada (vem do Picker)
    // ─────────────────────────────────────────

    async handleOppSelected(event) {
        const { recordId, name, objectType } = event.detail;
        this.opportunityName = name;

        try {
            const thread  = await getOrCreateThread({ recordId: recordId, objectType: objectType || '' });
            this.threadId = thread.Id;
            this.showChat = true;
            this._startPolling();
            await markThreadAsRead({ threadId: this.threadId });
            this.unreadCount = 0;
        } catch (err) {
            console.error('communicatorChat.handleOppSelected:', err);
        }
    }

    // ─────────────────────────────────────────
    // Chat room handlers
    // ─────────────────────────────────────────

    handleBack() {
        this._stopPolling();
        this.showChat      = false;
        this.threadId      = null;
        this.unreadCount   = 0;
        this.opportunityName = '';
    }

    handleMessageSent() {
        markThreadAsRead({ threadId: this.threadId }).catch(console.error);
        this.unreadCount = 0;
    }

    // ─────────────────────────────────────────
    // Polling
    // ─────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        const intervalMs = this._settings?.pollingIntervalMs || DEFAULT_POLL_MS;
        this._pollTimer = setInterval(async () => {
            // Atualiza a timeline
            this.template.querySelector('c-communicator-chat-room')?.refresh();
            // Atualiza badge de não lidos
            if (this.threadId) {
                try {
                    this.unreadCount = await getUnreadCount({ threadId: this.threadId });
                } catch (e) { /* silencioso */ }
            }
        }, intervalMs);
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

    get isFabMode() {
        return this.mode === MODE_FAB;
    }

    get isUtilityMode() {
        return this.mode === MODE_UTILITY;
    }

    get fabClass() {
        return ['comm-fab', this.isOpen ? 'comm-fab--active' : ''].join(' ').trim();
    }

    get fabIcon() {
        return this.isOpen ? 'utility:close' : 'utility:chat';
    }

    get showUnreadBadge() {
        return !this.isOpen && this.unreadCount > 0;
    }

    get displayUnread() {
        return this.unreadCount > 99 ? '99+' : String(this.unreadCount);
    }
}
